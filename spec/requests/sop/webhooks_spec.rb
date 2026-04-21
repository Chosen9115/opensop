require 'rails_helper'

RSpec.describe "Sop webhooks", type: :request do
  # Stub the outbound webhook call — the engine now fires a real HTTP
  # request when a webhook step executes. This suite is focused on the
  # inbound callback receiver, so we only need the outbound call to succeed.
  before { stub_request(:post, "https://example.com/provider").to_return(status: 200, body: "{}") }

  let(:process_def) do
    {
      "opensop" => "0.1",
      "process" => {
        "name" => "webhook-proc",
        "version" => "1.0",
        "description" => "webhook proc",
        "inputs" => [ { "name" => "alpha", "type" => "string", "required" => true } ],
        "outputs" => [],
        "steps" => [
          {
            "id" => "ping", "name" => "Ping", "type" => "webhook",
            "webhook" => {
              "method" => "POST",
              "url" => "https://example.com/provider",
              "response_mode" => "callback",
              "poll_timeout" => "1d"
            },
            "outputs" => []
          }
        ]
      }
    }
  end

  let!(:process) do
    create(:sop_process, name: "webhook-proc", version: "1.0",
           description: "webhook proc", definition: process_def)
  end

  let!(:instance) do
    Opensop::InstanceExecutor.start(process: process, inputs: { "alpha" => "ok" })
  end

  let(:callback) { instance.callbacks.first }

  describe "POST /sop/webhooks/:callback_id" do
    it "records the response, advances the step, and returns 200" do
      callback_id = callback.callback_path.split("/").last

      post "/sop/webhooks/#{callback_id}", params: { "entity_id" => "E-123" }

      expect(response).to have_http_status(:ok)
      expect(json[:status]).to eq("received")

      callback.reload
      expect(callback.status).to eq("received")
      expect(callback.response).to include("entity_id" => "E-123")

      step = instance.steps.find_by(step_id: "ping").tap(&:reload)
      expect(step.state).to eq("completed")
    end

    it "returns 404 for an unknown callback_id" do
      post "/sop/webhooks/#{SecureRandom.uuid}"

      expect(response).to have_http_status(:not_found)
      expect(json[:error]).to eq("not_found")
    end

    it "returns 409 when the callback has already been received" do
      callback_id = callback.callback_path.split("/").last
      callback.update!(status: "received", response: { "ok" => true })

      post "/sop/webhooks/#{callback_id}"

      expect(response).to have_http_status(:conflict)
      expect(json[:error]).to eq("callback_already_resolved")
    end

    it "does NOT require the X-SOP-Token header" do
      original = ENV["OPENSOP_API_TOKEN"]
      ENV["OPENSOP_API_TOKEN"] = "secret-token"
      begin
        callback_id = callback.callback_path.split("/").last
        post "/sop/webhooks/#{callback_id}", params: { "ok" => true }
        expect(response).to have_http_status(:ok)
      ensure
        if original.nil?
          ENV.delete("OPENSOP_API_TOKEN")
        else
          ENV["OPENSOP_API_TOKEN"] = original
        end
      end
    end
  end

  describe "POST /sop/webhooks/:callback_id with declared outputs" do
    # A minimal process where the webhook step declares the outputs the
    # third party is expected to POST at the top level.
    let(:declared_outputs_def) do
      {
        "opensop" => "0.1",
        "process" => {
          "name" => "webhook-declared-proc",
          "version" => "1.0",
          "description" => "webhook with declared outputs",
          "inputs" => [ { "name" => "alpha", "type" => "string", "required" => true } ],
          "outputs" => [
            { "name" => "result", "type" => "string",
              "from" => "steps.ping.outputs.result" },
            { "name" => "ref", "type" => "string",
              "from" => "steps.ping.outputs.ref" }
          ],
          "steps" => [
            {
              "id" => "ping", "name" => "Ping", "type" => "webhook",
              "webhook" => {
                "method" => "POST",
                "url" => "https://example.com/provider",
                "response_mode" => "callback",
                "poll_timeout" => "1d"
              },
              "outputs" => [
                { "name" => "result", "type" => "string" },
                { "name" => "ref", "type" => "string" }
              ]
            }
          ]
        }
      }
    end

    let!(:declared_outputs_process) do
      create(:sop_process, name: "webhook-declared-proc", version: "1.0",
             description: "webhook with declared outputs", definition: declared_outputs_def)
    end

    let!(:declared_outputs_instance) do
      Opensop::InstanceExecutor.start(process: declared_outputs_process,
                                      inputs: { "alpha" => "ok" })
    end

    let(:declared_outputs_callback) { declared_outputs_instance.callbacks.first }

    it "merges top-level payload keys into declared step outputs and completes the instance" do
      step = declared_outputs_instance.steps.find_by(step_id: "ping")
      expect(step.state).to eq("active")
      expect(step.sub_state).to eq("waiting_for_callback")

      callback_id = declared_outputs_callback.callback_path.split("/").last

      post "/sop/webhooks/#{callback_id}",
           params: { "result" => "ok", "ref" => "abc-123" }

      expect(response).to have_http_status(:ok)
      expect(json[:status]).to eq("received")

      declared_outputs_callback.reload
      expect(declared_outputs_callback.status).to eq("received")
      expect(declared_outputs_callback.response)
        .to include("result" => "ok", "ref" => "abc-123")

      step.reload
      expect(step.state).to eq("completed")
      expect(step.outputs).to eq("result" => "ok", "ref" => "abc-123")

      declared_outputs_instance.reload
      expect(declared_outputs_instance.state).to eq("completed")
      expect(declared_outputs_instance.outputs)
        .to include("result" => "ok", "ref" => "abc-123")
    end

    it "returns 422 when payload is missing a declared output but still persists the raw payload" do
      callback_id = declared_outputs_callback.callback_path.split("/").last

      # Missing "ref" — validate_outputs! should reject and surface 422.
      post "/sop/webhooks/#{callback_id}",
           params: { "result" => "ok" }

      expect(response.status).to eq(422)
      expect(json[:error]).to eq("invalid_callback_payload")
      expect(json[:message]).to match(/ref/)

      # Callback row is still updated with the raw payload — no data loss.
      declared_outputs_callback.reload
      expect(declared_outputs_callback.status).to eq("received")
      expect(declared_outputs_callback.response).to include("result" => "ok")

      # Step remains waiting — not completed.
      step = declared_outputs_instance.steps.find_by(step_id: "ping").tap(&:reload)
      expect(step.state).to eq("active")
      expect(step.sub_state).to eq("waiting_for_callback")
    end

    it "preserves prior step outputs and lets the payload override them" do
      # Pre-seed the step with an existing output that the payload does NOT touch.
      step = declared_outputs_instance.steps.find_by(step_id: "ping")
      step.update!(outputs: { "pre_existing" => "keep-me", "result" => "old" })

      callback_id = declared_outputs_callback.callback_path.split("/").last

      post "/sop/webhooks/#{callback_id}",
           params: { "result" => "new", "ref" => "abc-123" }

      expect(response).to have_http_status(:ok)
      step.reload
      expect(step.outputs).to include(
        "pre_existing" => "keep-me", # preserved from prior
        "result"       => "new",      # overridden by payload
        "ref"          => "abc-123"   # added by payload
      )
    end
  end
end
