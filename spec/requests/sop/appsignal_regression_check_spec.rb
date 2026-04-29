require "rails_helper"

RSpec.describe "AppSignal Regression Check process", type: :request do
  before { load_appsignal_processes! }

  let(:process) { Sop::Process.find_by!(name: "appsignal-regression-check") }

  let(:merged_at) { 10.days.ago.iso8601 }

  let(:base_inputs) do
    {
      "incident_id"     => "stub-coba-1",
      "incident_number" => 9_000_001,
      "app_id"          => "6274502ed2a5e428ee8b9aee",
      "repo"            => "coba-ai/coba",
      "project"         => "coba",
      "pr_number"       => 88,
      "merged_at"       => merged_at
    }
  end

  # Stub automated steps; override per example.
  let(:fetch_outputs) do
    {
      "current_last_seen"         => (Time.parse(merged_at) - 3600).iso8601,
      "current_state"             => "closed",
      "current_occurrences_count" => 0,
      "days_since_merge"          => 10.0
    }
  end

  let(:evaluate_outputs) do
    { "verdict" => "fix_verified", "verdict_reason" => "last_seen is before merged_at" }
  end

  before do
    allow_any_instance_of(Opensop::StepExecutors::Automated).to receive(:call) do |_executor, step, _instance, _defn|
      outputs = case step.step_id
      when "fetch-current-state" then fetch_outputs
      when "evaluate-regression"  then evaluate_outputs
      else {}
      end
      { outputs: outputs }
    end
  end

  describe "step ordering" do
    it "has wait → fetch → evaluate → report steps" do
      get "/sop/appsignal-regression-check/schema"
      expect(response).to have_http_status(:ok)
      step_ids = json.dig(:process, :steps).map { |s| s[:id] }
      expect(step_ids).to eq(%w[wait-grace-period fetch-current-state evaluate-regression report-outcome])
    end
  end

  describe "wait step completes immediately in test" do
    it "wait-grace-period is completed after start" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: base_inputs)
      wait_step = instance.steps.find_by!(step_id: "wait-grace-period")
      expect(wait_step.state).to eq("completed")
    end
  end

  describe "fix_verified verdict" do
    it "completes with fix_verified and triggers report-outcome" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: base_inputs)

      expect(instance.state).to eq("completed")
      step_states = instance.steps.pluck(:step_id, :state).to_h
      expect(step_states["evaluate-regression"]).to eq("completed")
      expect(step_states["report-outcome"]).to eq("completed")

      expect(instance.outputs["verdict"]).to eq("fix_verified")
    end
  end

  describe "regression_detected verdict" do
    let(:fetch_outputs) do
      {
        "current_last_seen"         => (Time.parse(merged_at) + 4 * 86_400).iso8601,
        "current_state"             => "open",
        "current_occurrences_count" => 7,
        "days_since_merge"          => 4.1
      }
    end

    let(:evaluate_outputs) do
      { "verdict" => "regression_detected", "verdict_reason" => "last_seen 4.1d after merge, exceeds 24h tolerance" }
    end

    it "completes with regression_detected and triggers report-outcome" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: base_inputs)

      expect(instance.state).to eq("completed")
      expect(instance.outputs["verdict"]).to eq("regression_detected")
      expect(instance.steps.find_by!(step_id: "report-outcome").state).to eq("completed")
    end
  end

  describe "deferred_grace verdict — report-outcome skipped" do
    let(:fetch_outputs) do
      {
        "current_last_seen"         => (Time.parse(merged_at) + 12 * 3600).iso8601,
        "current_state"             => "open",
        "current_occurrences_count" => 2,
        "days_since_merge"          => 0.5
      }
    end

    let(:evaluate_outputs) do
      { "verdict" => "deferred_grace", "verdict_reason" => "within 3-day grace window" }
    end

    it "completes with deferred_grace and skips report-outcome" do
      instance = Opensop::InstanceExecutor.start(process: process, inputs: base_inputs)

      expect(instance.state).to eq("completed")
      expect(instance.outputs["verdict"]).to eq("deferred_grace")
      expect(instance.steps.find_by!(step_id: "report-outcome").state).to eq("skipped")
    end
  end

  describe "API contract" do
    it "starts with valid inputs and returns 201" do
      post "/sop/appsignal-regression-check/start",
           params: { inputs: base_inputs }, as: :json
      expect(response).to have_http_status(:created)
    end

    it "rejects missing merged_at with 422" do
      post "/sop/appsignal-regression-check/start",
           params: { inputs: base_inputs.except("merged_at") }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json[:error]).to eq("invalid_inputs")
    end
  end
end
