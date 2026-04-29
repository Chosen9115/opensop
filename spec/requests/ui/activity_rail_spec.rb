require "rails_helper"

# Verifies that the right-hand activity rail (rendered into every Ui:: page
# via the application layout) emits the three-tab structure with Stimulus
# wiring, plus the per-tab panels with the right data sources.
RSpec.describe "Ui::ActivityRail", type: :request do
  describe "GET /dashboard renders the three-tab activity rail" do
    it "wires the Stimulus controller and exposes all three tabs as buttons" do
      get "/dashboard"
      expect(response).to have_http_status(:ok)

      # The aside carries the controller binding.
      expect(response.body).to include('data-controller="activity-rail"')

      # All three tabs render as <button>s with click actions.
      expect(response.body).to include('data-activity-rail-key-param="feed"')
      expect(response.body).to include('data-activity-rail-key-param="agents"')
      expect(response.body).to include('data-activity-rail-key-param="up_next"')

      expect(response.body).to include('click->activity-rail#switch')
    end

    it "renders three panels with data-key markers, with feed visible by default" do
      get "/dashboard"

      expect(response.body).to include('data-key="feed"')
      expect(response.body).to include('data-key="agents"')
      expect(response.body).to include('data-key="up_next"')

      # Agents and up_next start hidden via the `hidden` boolean attribute.
      expect(response.body).to match(/data-key="agents"[^>]*hidden/)
      expect(response.body).to match(/data-key="up_next"[^>]*hidden/)
    end

    it "renders empty states for all three tabs when no data is loaded" do
      get "/dashboard"

      expect(response.body).to include("No activity yet.")
      expect(response.body).to include("No agent calls yet.")
      expect(response.body).to include("Nothing queued.")
    end
  end

  describe "Agents tab" do
    it "renders the model name and target for each LLM call" do
      process = Sop::Process.create!(
        name: "demo",
        version: "1",
        status: "active",
        definition: { "process" => { "id" => "demo", "version" => "1", "steps" => [] } }
      )
      instance = Sop::Instance.create!(
        process: process,
        process_name: "demo",
        process_version: "1",
        state: "running"
      )
      step = instance.steps.create!(
        step_id: "summarize",
        step_name: "Summarize",
        step_type: "llm",
        state: "active",
        position: 1,
        attempt: 1
      )
      Sop::LlmCall.create!(
        step: step,
        model: "gpt-4o-mini",
        prompt_hash: "abc123",
        started_at: 1.minute.ago,
        attempt: 1,
        status: "succeeded"
      )

      get "/dashboard"

      expect(response.body).to include("gpt-4o-mini")
      expect(response.body).to include("demo/summarize")
    end
  end

  describe "Up next tab" do
    it "renders an enabled schedule by name + process" do
      Sop::Schedule.create!(
        name: "Daily report",
        process_name: "daily_report",
        cron_expression: "0 9 * * *",
        timezone: "UTC",
        enabled: true
      )

      get "/dashboard"

      expect(response.body).to include("Daily report")
      expect(response.body).to include("daily_report")
    end

    it "renders a step waiting for input" do
      process = Sop::Process.create!(
        name: "approval",
        version: "1",
        status: "active",
        definition: { "process" => { "id" => "approval", "version" => "1", "steps" => [] } }
      )
      instance = Sop::Instance.create!(
        process: process,
        process_name: "approval",
        process_version: "1",
        state: "running"
      )
      instance.steps.create!(
        step_id: "review",
        step_name: "Review",
        step_type: "approval",
        state: "active",
        sub_state: "waiting_for_approval",
        position: 1,
        attempt: 1
      )

      get "/dashboard"

      expect(response.body).to include("review")
      expect(response.body).to include("approval")
    end
  end
end
