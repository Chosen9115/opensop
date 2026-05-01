require "rails_helper"

RSpec.describe "GET /sop/steps/pending", type: :request do
  # Minimal process with one automated step and no run: path.
  # Steps of this type park at waiting_for_worker until a worker submits outputs.
  let(:process_yaml) do
    <<~YAML
      opensop: "0.1"
      process:
        name: smoke-external-worker
        version: "1.0"
        description: "Smoke test for external worker step polling"
        owner: test-suite
        trigger:
          type: api
        inputs:
          - name: payload
            type: string
            required: true
        steps:
          - id: do-work
            name: "Do work via external worker"
            type: automated
            inputs:
              - name: payload
                from: process.inputs.payload
            outputs:
              - name: result
                type: string
    YAML
  end

  before do
    post "/sop/processes/register", params: { yaml: process_yaml }
  end

  let(:process) { Sop::Process.find_by!(name: "smoke-external-worker") }
  let(:valid_inputs) { { "payload" => "test-#{SecureRandom.hex(4)}" } }

  context "when no steps are waiting for a worker" do
    it "returns an empty list" do
      get "/sop/steps/pending"

      expect(response).to have_http_status(:ok)
      expect(json[:steps]).to eq([])
    end
  end

  context "when an automated step has no run: path" do
    before { Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs) }

    it "returns the waiting step with its resolved inputs" do
      get "/sop/steps/pending"

      expect(response).to have_http_status(:ok)
      expect(json[:steps].size).to be >= 1

      step = json[:steps].first
      expect(step[:process_name]).to eq("smoke-external-worker")
      expect(step[:step_id]).to eq("do-work")
      expect(step[:inputs]).to include(payload: valid_inputs["payload"])
    end

    it "includes instance_id and step_name" do
      get "/sop/steps/pending"

      step = json[:steps].first
      expect(step[:instance_id]).to be_present
      expect(step[:step_name]).to be_present
    end
  end

  context "with ?process_name= filter" do
    before { Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs) }

    it "returns only steps for the specified process" do
      get "/sop/steps/pending", params: { process_name: "smoke-external-worker" }

      expect(response).to have_http_status(:ok)
      expect(json[:steps]).to all(include(process_name: "smoke-external-worker"))
    end

    it "returns empty list when process_name does not match" do
      get "/sop/steps/pending", params: { process_name: "nonexistent-process" }

      expect(response).to have_http_status(:ok)
      expect(json[:steps]).to eq([])
    end
  end

  context "after a worker submits a step" do
    it "step is no longer returned by the pending endpoint" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs)

      get "/sop/steps/pending"
      expect(json[:steps].map { |s| s[:step_id] }).to include("do-work")

      post "/sop/smoke-external-worker/#{instance.id}/steps/do-work/submit",
           params: { outputs: { "result" => "done" } },
           as: :json
      expect(response).to have_http_status(:ok)

      get "/sop/steps/pending"
      expect(json[:steps].map { |s| s[:step_id] }).not_to include("do-work")
    end
  end
end
