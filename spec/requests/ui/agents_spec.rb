require "rails_helper"

# NOTE: Until the integration agent wires
#   `get "/agents", to: "ui/agents#index", as: :ui_agents`
# into config/routes/ui.rb (and registers the corresponding sidebar entry +
# i18n keys), every example here will fail with `ActionController::RoutingError`.
# This is expected. Once the route is added, all examples should pass.
RSpec.describe "Ui::Agents", type: :request do
  before do
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
  end

  describe "GET /agents" do
    context "when there are no LLM calls" do
      it "responds with 200 and renders the empty state" do
        get "/agents"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Agents")
        # Zero tiles render.
        expect(response.body).to include("$0.00")
        # Empty state copy.
        expect(response.body).to include("No agent activity yet")
      end
    end

    context "when LLM calls exist within the 30-day window" do
      let!(:instance) { create(:sop_instance, :running) }
      let!(:step_a) { create(:sop_step, instance: instance, step_name: "draft_email", confidence: 0.9) }
      let!(:step_b) { create(:sop_step, instance: instance, step_name: "summarise", confidence: 0.6) }

      before do
        # gpt-4o — 3 calls (each on the same step but different attempt numbers
        # to satisfy the unique index on (step_id, attempt))
        Sop::LlmCall.create!(step: step_a, model: "gpt-4o", prompt_hash: "p1",
                             attempt: 1, status: "succeeded",
                             input_tokens: 1_200, output_tokens: 800,
                             cost_cents: 250, started_at: 2.days.ago)
        Sop::LlmCall.create!(step: step_a, model: "gpt-4o", prompt_hash: "p2",
                             attempt: 2, status: "succeeded",
                             input_tokens: 600, output_tokens: 400,
                             cost_cents: 120, started_at: 5.days.ago)
        Sop::LlmCall.create!(step: step_a, model: "gpt-4o", prompt_hash: "p3",
                             attempt: 3, status: "errored",
                             input_tokens: 0, output_tokens: 0,
                             cost_cents: 0, started_at: 6.days.ago)

        # claude-3-5-sonnet — 1 call
        Sop::LlmCall.create!(step: step_b, model: "claude-3-5-sonnet", prompt_hash: "p4",
                             attempt: 1, status: "succeeded",
                             input_tokens: 5_000, output_tokens: 1_500,
                             cost_cents: 90, started_at: 10.days.ago)

        # Outside the window — must be excluded.
        Sop::LlmCall.create!(step: step_b, model: "claude-3-5-sonnet", prompt_hash: "p5",
                             attempt: 2, status: "succeeded",
                             input_tokens: 9_999, output_tokens: 9_999,
                             cost_cents: 9_999, started_at: 60.days.ago)
      end

      it "responds with 200 and renders one card per model" do
        get "/agents"

        expect(response).to have_http_status(:ok)

        # Both model names appear (in mono).
        expect(response.body).to include("gpt-4o")
        expect(response.body).to include("claude-3-5-sonnet")

        # Total spend tile = 250 + 120 + 0 + 90 = 460 cents = $4.60
        expect(response.body).to include("$4.60")

        # Out-of-window record stays out.
        expect(response.body).not_to include("$99.99")
      end
    end

    context "when the underlying table is unavailable" do
      it "still renders the page with zeroed tiles" do
        allow(Sop::LlmCall).to receive(:where)
          .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))

        get "/agents"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Agents")
        expect(response.body).to include("$0.00")
      end
    end
  end
end
