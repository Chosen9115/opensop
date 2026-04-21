require "rails_helper"

RSpec.describe "Sop triggers", type: :request do
  let(:secret) { "whsec_test_abc" }

  let(:process_def) do
    {
      "opensop" => "0.1",
      "process" => {
        "name" => "consult-request",
        "version" => "1.0",
        "description" => "Inbound booking from Cal.com",
        "trigger" => {
          "type" => "webhook",
          "auth" => {
            "scheme"     => "hmac-sha256",
            "secret_env" => "TEST_CAL_SECRET",
            "header"     => "X-Cal-Signature-256",
            "encoding"   => "hex",
            "prefix"     => "sha256="
          },
          "input_mapping" => {
            "attendee_email" => "${payload.attendees.0.email}",
            "attendee_name"  => "${payload.attendees.0.name}",
            "meeting_time"   => "${payload.startTime}",
            "source"         => "cal.com"
          }
        },
        "inputs" => [
          { "name" => "attendee_email", "type" => "string", "required" => true },
          { "name" => "attendee_name",  "type" => "string", "required" => true },
          { "name" => "meeting_time",   "type" => "string", "required" => true },
          { "name" => "source",         "type" => "string" }
        ],
        "steps" => []
      }
    }
  end

  let!(:process) do
    create(:sop_process,
           name: "consult-request",
           version: "1.0",
           description: "Inbound booking from Cal.com",
           definition: process_def)
  end

  let(:valid_payload) do
    {
      "type" => "BOOKING_CREATED",
      "uid"  => "bkg_abc123",
      "startTime" => "2026-05-01T15:00:00Z",
      "attendees" => [
        { "email" => "ana@example.com", "name" => "Ana García" }
      ]
    }
  end

  def sign(body, sec = secret)
    "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", sec, body)
  end

  before { ENV["TEST_CAL_SECRET"] = secret }
  after  { ENV.delete("TEST_CAL_SECRET") }

  describe "POST /sop/triggers/:process_name" do
    it "verifies the HMAC, resolves the input mapping, and starts an instance" do
      raw = valid_payload.to_json

      expect {
        post "/sop/triggers/consult-request",
             params: raw,
             headers: { "Content-Type" => "application/json", "X-Cal-Signature-256" => sign(raw) }
      }.to change(Sop::Instance, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("started")
      expect(body["instance_id"]).to match(/\A[0-9a-f-]{36}\z/)

      instance = Sop::Instance.find(body["instance_id"])
      expect(instance.inputs).to eq(
        "attendee_email" => "ana@example.com",
        "attendee_name"  => "Ana García",
        "meeting_time"   => "2026-05-01T15:00:00Z",
        "source"         => "cal.com"
      )
      expect(instance.metadata).to include("source" => "trigger")
    end

    it "rejects a request with an invalid HMAC signature" do
      raw = valid_payload.to_json

      expect {
        post "/sop/triggers/consult-request",
             params: raw,
             headers: { "Content-Type" => "application/json", "X-Cal-Signature-256" => "sha256=deadbeef" }
      }.not_to change(Sop::Instance, :count)

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_signature")
    end

    it "rejects a request with a missing signature header" do
      raw = valid_payload.to_json

      post "/sop/triggers/consult-request",
           params: raw,
           headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_signature")
    end

    it "rejects a request with a tampered body" do
      raw = valid_payload.to_json
      sig = sign(raw)
      tampered = raw.sub("Ana García", "Evil McHacker")

      post "/sop/triggers/consult-request",
           params: tampered,
           headers: { "Content-Type" => "application/json", "X-Cal-Signature-256" => sig }

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 200 and logs when the payload is missing a mapped key (Q2 option C)" do
      payload_without_attendees = { "type" => "BOOKING_CREATED", "uid" => "bkg_x" }
      raw = payload_without_attendees.to_json

      expect(Rails.logger).to receive(:warn).with(/MAPPING_REJECTED/).at_least(:once)

      expect {
        post "/sop/triggers/consult-request",
             params: raw,
             headers: { "Content-Type" => "application/json", "X-Cal-Signature-256" => sign(raw) }
      }.not_to change(Sop::Instance, :count)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("accepted")
      expect(body["action"]).to eq("logged")
    end

    it "returns 404 for an unknown process" do
      raw = valid_payload.to_json

      post "/sop/triggers/does-not-exist",
           params: raw,
           headers: { "Content-Type" => "application/json", "X-Cal-Signature-256" => sign(raw) }

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a process that doesn't declare a webhook trigger" do
      plain_proc_def = process_def.deep_dup
      plain_proc_def["process"]["name"] = "no-trigger"
      plain_proc_def["process"]["trigger"] = { "type" => "api" }
      create(:sop_process, name: "no-trigger", version: "1.0", definition: plain_proc_def)

      raw = valid_payload.to_json
      post "/sop/triggers/no-trigger",
           params: raw,
           headers: { "Content-Type" => "application/json", "X-Cal-Signature-256" => sign(raw) }

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("trigger_not_configured")
    end

    it "returns 400 for non-JSON body" do
      post "/sop/triggers/consult-request",
           params: "not json",
           headers: { "Content-Type" => "application/json", "X-Cal-Signature-256" => sign("not json") }

      expect(response).to have_http_status(:bad_request)
    end

    it "returns 500 when the configured secret env var is unset" do
      ENV.delete("TEST_CAL_SECRET")
      raw = valid_payload.to_json

      post "/sop/triggers/consult-request",
           params: raw,
           headers: { "Content-Type" => "application/json", "X-Cal-Signature-256" => "sha256=deadbeef" }

      expect(response).to have_http_status(:internal_server_error)
      expect(JSON.parse(response.body)["error"]).to eq("trigger_misconfigured")
    end

    it "does not require X-SOP-Token (HMAC is the auth)" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("OPENSOP_API_TOKEN").and_return("sk_live_xxx")

      raw = valid_payload.to_json
      post "/sop/triggers/consult-request",
           params: raw,
           headers: { "Content-Type" => "application/json", "X-Cal-Signature-256" => sign(raw) }

      expect(response).to have_http_status(:ok)
    end
  end
end
