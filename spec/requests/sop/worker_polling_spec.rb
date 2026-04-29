require "rails_helper"

RSpec.describe "GET /sop/steps/pending", type: :request do
  before { load_appsignal_processes! }

  let(:process) { Sop::Process.find_by!(name: "appsignal-responder") }

  let(:valid_inputs) do
    { "projects" => ["coba"], "phase" => "1", "run_id" => "smoke-poll-#{SecureRandom.hex(4)}" }
  end

  context "when no steps are waiting for a worker" do
    it "returns an empty list" do
      get "/sop/steps/pending"

      expect(response).to have_http_status(:ok)
      expect(json[:steps]).to eq([])
    end
  end

  context "when automated steps have no run: path" do
    before do
      # Start without stubbing automated executor — steps will park at waiting_for_worker.
      Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs)
    end

    it "returns the waiting step with its resolved inputs" do
      get "/sop/steps/pending"

      expect(response).to have_http_status(:ok)
      expect(json[:steps].size).to be >= 1

      step = json[:steps].first
      expect(step[:process_name]).to eq("appsignal-responder")
      expect(step[:step_id]).to eq("fetch-incidents")
      expect(step[:inputs]).to include(projects: ["coba"])
    end

    it "includes instance_id and step_name" do
      get "/sop/steps/pending"

      step = json[:steps].first
      expect(step[:instance_id]).to be_present
      expect(step[:step_name]).to be_present
    end
  end

  context "with ?process_name= filter" do
    before do
      Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs)
    end

    it "returns only steps for the specified process" do
      get "/sop/steps/pending", params: { process_name: "appsignal-responder" }

      expect(response).to have_http_status(:ok)
      expect(json[:steps]).to all(include(process_name: "appsignal-responder"))
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
      expect(json[:steps].map { |s| s[:step_id] }).to include("fetch-incidents")

      # Worker submits fetch-incidents — next step (build-known-work) becomes pending.
      post "/sop/appsignal-responder/#{instance.id}/steps/fetch-incidents/submit",
           params: { outputs: { "incidents" => [], "total_fetched" => 0 } },
           as: :json
      expect(response).to have_http_status(:ok)

      get "/sop/steps/pending"
      step_ids = json[:steps].map { |s| s[:step_id] }
      expect(step_ids).not_to include("fetch-incidents")
      expect(step_ids).to include("build-known-work")
    end
  end
end
