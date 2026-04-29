require "rails_helper"

RSpec.describe "consult-request v1.1 — fire-and-forget", type: :request do
  around do |example|
    orig = ENV.to_h.slice("DENCHCLAW_BRIDGE_URL", "DENCHCLAW_BRIDGE_TOKEN", "CAL_WEBHOOK_SECRET")
    ENV["DENCHCLAW_BRIDGE_URL"]   = "https://bridge.test"
    ENV["DENCHCLAW_BRIDGE_TOKEN"] = "test-token"
    ENV["CAL_WEBHOOK_SECRET"]     = "dummy-secret"
    example.run
  ensure
    orig.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end

  before do
    Opensop::Registry.load_file(
      Rails.root.join("processes/coba/consult-request.sop.yaml")
    )
    stub_request(:post, "https://bridge.test/leads")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: JSON.dump("person_id" => "p-1", "deal_id" => "d-1", "was_duplicate" => false)
      )
  end

  let(:valid_inputs) do
    {
      "attendee_email" => "prospect@example.com",
      "attendee_name"  => "Jane Prospect",
      "meeting_time"   => "2026-05-01T10:00:00Z",
      "booking_id"     => "booking-abc-123",
      "event_type"     => "Coba Consult — 30min",
      "source"         => "cal.com"
    }
  end

  describe "POST /sop/consult-request/start" do
    it "creates an instance and returns 201" do
      post "/sop/consult-request/start", params: { inputs: valid_inputs }

      expect(response).to have_http_status(:created)
      expect(json[:process][:name]).to eq("consult-request")
    end

    it "completes after create-crm-record" do
      post "/sop/consult-request/start", params: { inputs: valid_inputs }
      instance_id = json[:id]

      get "/sop/consult-request/#{instance_id}"
      expect(json[:state]).to eq("completed")
    end

    it "surfaces crm outputs on the completed instance" do
      post "/sop/consult-request/start", params: { inputs: valid_inputs }
      instance_id = json[:id]

      get "/sop/consult-request/#{instance_id}"

      expect(json[:outputs]).to include(
        crm_deal_id:   "d-1",
        crm_person_id: "p-1",
        was_duplicate: false
      )
    end

    it "does NOT leave hanging steps after completion" do
      post "/sop/consult-request/start", params: { inputs: valid_inputs }
      instance_id = json[:id]

      get "/sop/consult-request/#{instance_id}/steps"

      step_states = json[:steps].map { |s| s[:state] }
      expect(step_states).to all(eq("completed"))
    end

    it "returns 422 when attendee_email is missing" do
      post "/sop/consult-request/start",
           params: { inputs: valid_inputs.except("attendee_email") }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
