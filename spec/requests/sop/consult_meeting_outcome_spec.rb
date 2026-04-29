require "rails_helper"

RSpec.describe "consult-meeting-outcome v1.1 — enrich + propose + route", type: :request do
  around do |example|
    orig = ENV.to_h.slice("DENCHCLAW_BRIDGE_URL", "DENCHCLAW_BRIDGE_TOKEN")
    ENV["DENCHCLAW_BRIDGE_URL"]   = "https://bridge.test"
    ENV["DENCHCLAW_BRIDGE_TOKEN"] = "test-token"
    example.run
  ensure
    orig.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end

  before do
    Opensop::Registry.load_file(
      Rails.root.join("processes/coba/consult-meeting-outcome.sop.yaml")
    )
    stub_request(:post, "https://bridge.test/circleback/match")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.dump(
          "matched"          => true,
          "meeting_id"       => "meet-xyz",
          "name"             => "Coba Consult — Jane Prospect",
          "created_at"       => "2026-05-01T10:05:00Z",
          "duration_seconds" => 2700,
          "url"              => "https://circleback.ai/meetings/meet-xyz",
          "ical_uid"         => "uid@cal",
          "attendees"        => [ { "name" => "Jane Prospect", "email" => "prospect@example.com" } ],
          "notes"            => "Discussed cross-border FX needs.",
          "action_items"     => [],
          "insights"         => []
        )
      )
  end

  let(:valid_inputs) do
    {
      "attendee_email" => "prospect@example.com",
      "meeting_time"   => "2026-05-01T10:00:00Z"
    }
  end

  let(:propose_outputs) do
    {
      "attended"        => true,
      "qualified"       => "yes-hot",
      "decision_volume" => "250k-1m",
      "notes"           => "High intent, cross-border FX volume confirmed.",
      "next_step"       => "schedule-follow-up",
      "rationale"       => "Strong signals: volume + timeline.",
      "confidence"      => 0.85,
      "prompt_used"     => "Summarise the meeting...",
      "model"           => "claude-sonnet-4-6",
      "usage"           => { "input_tokens" => 1200, "output_tokens" => 340, "cost_usd" => 0.0 },
      "raw_response"    => '{"attended":true}'
    }
  end

  let(:route_outputs) do
    { "routed_to" => "follow-up", "rationale" => "next_step=schedule-follow-up → follow-up" }
  end

  describe "full happy path: enrich → propose-outcome → route" do
    it "completes all three steps and the instance" do
      post "/sop/consult-meeting-outcome/start", params: { inputs: valid_inputs }
      expect(response).to have_http_status(:created)
      instance_id = json[:id]

      # enrich (webhook/sync) fires automatically on start; propose-outcome is now active.
      get "/sop/consult-meeting-outcome/#{instance_id}"
      expect(json[:state]).to eq("running")

      post "/sop/consult-meeting-outcome/#{instance_id}/steps/propose-outcome/submit",
           params: { outputs: propose_outputs }, as: :json
      expect(response).to have_http_status(:ok)

      post "/sop/consult-meeting-outcome/#{instance_id}/steps/route/submit",
           params: { outputs: route_outputs }, as: :json
      expect(response).to have_http_status(:ok)

      get "/sop/consult-meeting-outcome/#{instance_id}"
      expect(json[:state]).to eq("completed")
    end

    it "surfaces process-level outputs after completion" do
      post "/sop/consult-meeting-outcome/start", params: { inputs: valid_inputs }
      instance_id = json[:id]

      post "/sop/consult-meeting-outcome/#{instance_id}/steps/propose-outcome/submit",
           params: { outputs: propose_outputs }, as: :json
      post "/sop/consult-meeting-outcome/#{instance_id}/steps/route/submit",
           params: { outputs: route_outputs }, as: :json

      get "/sop/consult-meeting-outcome/#{instance_id}"
      expect(json[:outputs]).to include(
        matched:   true,
        attended:  true,
        qualified: "yes-hot",
        routed_to: "follow-up"
      )
    end

    it "records enrich outputs including meeting_id and matched flag" do
      post "/sop/consult-meeting-outcome/start", params: { inputs: valid_inputs }
      instance_id = json[:id]

      get "/sop/consult-meeting-outcome/#{instance_id}/steps"
      enrich_step = json[:steps].find { |s| s[:step_id] == "enrich" }

      expect(enrich_step[:state]).to eq("completed")
      expect(enrich_step[:outputs]).to include(matched: true, meeting_id: "meet-xyz")
    end
  end

  describe "missing required inputs" do
    it "returns 422 when attendee_email is absent" do
      post "/sop/consult-meeting-outcome/start",
           params: { inputs: { "meeting_time" => "2026-05-01T10:00:00Z" } }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
