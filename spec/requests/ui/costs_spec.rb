require "rails_helper"

# NOTE: Until the integration agent wires
#   `get "/costs", to: "ui/costs#index", as: :ui_costs`
# into config/routes/ui.rb (and registers the corresponding sidebar entry +
# i18n keys), every example here will fail with `ActionController::RoutingError`.
# This is expected. Once the route is added, all examples should pass.
RSpec.describe "Ui::Costs", type: :request do
  before do
    sign_in_via_magic_link(create(:user))
  end

  describe "GET /costs" do
    context "when there are no LLM calls" do
      it "responds with 200 and renders the empty state" do
        get "/costs"

        expect(response).to have_http_status(:ok)
        # Title + zero values + empty state copy.
        expect(response.body).to include("Costs")
        expect(response.body).to include("$0.00") # zero spend tile
        expect(response.body).to include("No LLM calls in the last 30 days")
      end
    end

    context "when LLM calls exist within the 30-day window" do
      let!(:instance) { create(:sop_instance, :running) }
      let!(:step_a) { create(:sop_step, instance: instance, step_name: "draft_email") }
      let!(:step_b) { create(:sop_step, instance: instance, step_name: "summarise") }

      before do
        Sop::LlmCall.create!(
          step: step_a,
          model: "gpt-4o",
          prompt_hash: "p1",
          attempt: 1,
          status: "succeeded",
          input_tokens: 1_200,
          output_tokens: 800,
          cost_cents: 250,
          started_at: 2.days.ago
        )
        Sop::LlmCall.create!(
          step: step_a,
          model: "gpt-4o",
          prompt_hash: "p2",
          attempt: 2,
          status: "succeeded",
          input_tokens: 600,
          output_tokens: 400,
          cost_cents: 120,
          started_at: 5.days.ago
        )
        Sop::LlmCall.create!(
          step: step_b,
          model: "claude-3-5-sonnet",
          prompt_hash: "p3",
          attempt: 1,
          status: "succeeded",
          input_tokens: 5_000,
          output_tokens: 1_500,
          cost_cents: 90,
          started_at: 10.days.ago
        )
        # Outside the window — must be excluded.
        Sop::LlmCall.create!(
          step: step_b,
          model: "claude-3-5-sonnet",
          prompt_hash: "p4",
          attempt: 2,
          status: "succeeded",
          input_tokens: 9_999,
          output_tokens: 9_999,
          cost_cents: 9_999,
          started_at: 60.days.ago
        )
      end

      it "responds with 200 and renders aggregated totals + step rows" do
        get "/costs"

        expect(response).to have_http_status(:ok)

        # 250 + 120 + 90 = 460 cents = $4.60
        expect(response.body).to include("$4.60")
        # 3 calls in window
        expect(response.body).to include("3")
        # Top step name surfaces (mono).
        expect(response.body).to include("draft_email")
        # Most-expensive step total: 250 + 120 = 370 cents -> $3.700
        expect(response.body).to include("$3.700")
        # Second step shown: 90 cents -> $0.900
        expect(response.body).to include("$0.900")
        # First 8 chars of instance id.
        expect(response.body).to include(instance.id.to_s.first(8))
        # Out-of-window record stays out.
        expect(response.body).not_to include("$99.99")
      end
    end

    context "when the underlying table is unavailable" do
      it "still renders the page with zeroed tiles" do
        allow(Sop::LlmCall).to receive(:where)
          .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))

        get "/costs"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Costs")
        expect(response.body).to include("$0.00")
      end
    end
  end
end
