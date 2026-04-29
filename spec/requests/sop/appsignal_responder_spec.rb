require "rails_helper"

RSpec.describe "AppSignal Responder process", type: :request do
  before { load_appsignal_processes! }

  let(:process) { Sop::Process.find_by!(name: "appsignal-responder") }

  let(:stub_outputs) do
    {
      "fetch-incidents"   => { "incidents" => [ incident_stub ], "total_fetched" => 1 },
      "build-known-work"  => { "known_work" => [], "known_work_count" => 0 },
      "apply-budget-caps" => { "incidents_to_process" => [ incident_stub ], "deferred_count" => 0, "run_blocked" => false }
    }
  end

  let(:incident_stub) do
    {
      "incident_id"       => "stub-coba-1",
      "incident_number"   => 9_000_001,
      "app_id"            => "6274502ed2a5e428ee8b9aee",
      "project"           => "coba",
      "repo"              => "coba-ai/coba",
      "project_path"      => "/tmp/coba",
      "exception_name"    => "NoMethodError",
      "message"           => "undefined method `foo` for nil:NilClass",
      "occurrences_count" => 15,
      "last_seen"         => 1.hour.ago.iso8601,
      "state"             => "open"
    }
  end

  let(:valid_inputs) do
    { "projects" => [ "coba" ], "phase" => "1", "run_id" => "smoke-#{SecureRandom.hex(4)}" }
  end

  before do
    allow_any_instance_of(Opensop::StepExecutors::Automated).to receive(:call) do |_executor, step, _instance, _defn|
      { outputs: stub_outputs.fetch(step.step_id, {}) }
    end
  end

  describe "POST /sop/appsignal-responder/start" do
    it "creates an instance and returns 201" do
      post "/sop/appsignal-responder/start",
           params: { inputs: valid_inputs }, as: :json

      expect(response).to have_http_status(:created)
      expect(json[:state]).to be_in(%w[running completed])
      expect(json.dig(:process, :name)).to eq("appsignal-responder")
    end

    it "rejects missing required inputs with 422" do
      post "/sop/appsignal-responder/start",
           params: { inputs: { "phase" => "1" } }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json[:error]).to eq("invalid_inputs")
    end

    it "rejects invalid phase enum value with 422" do
      post "/sop/appsignal-responder/start",
           params: { inputs: valid_inputs.merge("phase" => "9") }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json[:error]).to eq("invalid_inputs")
    end
  end

  describe "happy path — incidents passthrough" do
    it "completes with incidents_to_process in outputs" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs)

      expect(instance.state).to eq("completed")
      expect(instance.outputs["incidents_to_process"]).to be_a(Array)
      expect(instance.outputs["incidents_to_process"].first["incident_id"]).to eq("stub-coba-1")
      expect(instance.outputs["total_fetched"]).to eq(1)
      expect(instance.outputs["deferred_count"]).to eq(0)
    end

    it "passes run_id through to outputs" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs)

      expect(instance.outputs["run_id"]).to eq(valid_inputs["run_id"])
    end
  end

  describe "no incidents returned" do
    let(:stub_outputs) do
      {
        "fetch-incidents"   => { "incidents" => [], "total_fetched" => 0 },
        "build-known-work"  => { "known_work" => [], "known_work_count" => 0 },
        "apply-budget-caps" => { "incidents_to_process" => [], "deferred_count" => 0, "run_blocked" => false }
      }
    end

    it "completes with empty incidents_to_process" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs)

      expect(instance.state).to eq("completed")
      expect(instance.outputs["incidents_to_process"]).to eq([])
      expect(instance.outputs["total_fetched"]).to eq(0)
    end
  end

  describe "budget cap defers excess incidents" do
    let(:stub_outputs) do
      {
        "fetch-incidents"   => { "incidents" => Array.new(45) { incident_stub }, "total_fetched" => 45 },
        "build-known-work"  => { "known_work" => [], "known_work_count" => 0 },
        "apply-budget-caps" => { "incidents_to_process" => Array.new(40) { incident_stub }, "deferred_count" => 5, "run_blocked" => false }
      }
    end

    it "reports deferred_count from apply-budget-caps" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs)

      expect(instance.state).to eq("completed")
      expect(instance.outputs["deferred_count"]).to eq(5)
      expect(instance.outputs["incidents_to_process"].size).to eq(40)
    end
  end

  describe "step-level observability" do
    it "all three steps complete" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs)

      step_states = instance.steps.pluck(:step_id, :state).to_h
      expect(step_states["fetch-incidents"]).to eq("completed")
      expect(step_states["build-known-work"]).to eq("completed")
      expect(step_states["apply-budget-caps"]).to eq("completed")
    end
  end
end
