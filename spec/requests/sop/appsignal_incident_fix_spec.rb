require "rails_helper"

RSpec.describe "AppSignal Incident Fix process", type: :request do
  before { load_appsignal_processes! }

  let(:process) { Sop::Process.find_by!(name: "appsignal-incident-fix") }

  let(:base_inputs) do
    {
      "incident"        => {
        "incident_id"    => "stub-coba-1",
        "exception_name" => "NoMethodError",
        "message"        => "undefined method `foo` for nil:NilClass",
        "action_name"    => "SomeController#show"
      },
      "incident_id"     => "stub-coba-1",
      "incident_number" => 9_000_001,
      "app_id"          => "6274502ed2a5e428ee8b9aee",
      "project"         => "coba",
      "project_path"    => "/tmp/coba",
      "repo"            => "coba-ai/coba",
      "exception_name"  => "NoMethodError",
      "phase"           => "2"
    }
  end

  # Stub outputs for automated steps — override per example as needed.
  let(:gate_outputs)     { { "gate_passed" => true,  "gate_reason" => "" } }
  let(:worktree_outputs) { { "worktree_path" => "/tmp/wt-fix", "branch_name" => "fix/appsignal-stub001" } }
  let(:swarm_outputs)    { { "swarm_exit_code" => 0, "diff_summary" => "Fixed nil check.", "committed" => true } }
  let(:safety_outputs)   { { "files_changed" => 1, "additions" => 10, "critical_path_hit" => false, "gate_passed" => true, "gate_reason" => "" } }
  let(:push_outputs)     { { "pr_url" => "https://github.com/coba-ai/coba/pull/99", "pr_number" => 99 } }

  before do
    allow_any_instance_of(Opensop::StepExecutors::Automated).to receive(:call) do |_executor, step, _instance, _defn|
      outputs = case step.step_id
      when "pre-dispatch-gate"  then gate_outputs
      when "create-fix-worktree" then worktree_outputs
      when "run-swarm"          then swarm_outputs
      when "safety-gate"        then safety_outputs
      when "push-and-create-pr" then push_outputs
      else {}
      end
      { outputs: outputs }
    end
  end

  # Helper: start instance, advance classify-incident judgment, reload.
  def start_and_classify(decision:, reason:, file: nil, line: nil, inputs: base_inputs)
    instance = Opensop::InstanceExecutor.start(process: process, inputs: inputs)
    classify_step = instance.steps.find_by!(step_id: "classify-incident")
    expect(classify_step.sub_state).to eq("escalated")

    post "/sop/appsignal-incident-fix/#{instance.id}/steps/classify-incident/submit",
         params: { outputs: { "decision" => decision, "reason" => reason, "file" => file, "line" => line } },
         as: :json
    expect(response).to have_http_status(:ok)
    instance.reload
  end

  describe "decision: skip" do
    it "completes without advancing past classify" do
      instance = start_and_classify(decision: "skip", reason: "noise")

      expect(instance.state).to eq("completed")

      step_states = instance.steps.pluck(:step_id, :state).to_h
      expect(step_states["classify-incident"]).to eq("completed")
      expect(step_states["pre-dispatch-gate"]).to eq("skipped")
      expect(step_states["create-fix-worktree"]).to eq("skipped")
      expect(step_states["run-swarm"]).to eq("skipped")
      expect(step_states["safety-gate"]).to eq("skipped")
      expect(step_states["push-and-create-pr"]).to eq("skipped")
      expect(step_states["notify-team"]).to eq("completed")
    end

    it "surfaces decision in process outputs" do
      instance = start_and_classify(decision: "skip", reason: "noise")

      expect(instance.outputs["decision"]).to eq("skip")
      expect(instance.outputs["reason"]).to eq("noise")
    end
  end

  describe "decision: skip-duplicate" do
    it "completes and skips all dispatch steps" do
      instance = start_and_classify(decision: "skip-duplicate", reason: "already tracked in #88")

      expect(instance.state).to eq("completed")
      expect(instance.steps.find_by!(step_id: "pre-dispatch-gate").state).to eq("skipped")
    end
  end

  describe "Phase 1 — classify-only, dispatch blocked" do
    let(:phase1_inputs) { base_inputs.merge("phase" => "1") }

    it "pre-dispatch-gate blocks and no worktree is created" do
      # pre-dispatch-gate returns phase_1_only block
      allow_any_instance_of(Opensop::StepExecutors::Automated).to receive(:call) do |_executor, step, _instance, _defn|
        outputs = case step.step_id
        when "pre-dispatch-gate" then { "gate_passed" => false, "gate_reason" => "phase_1_only" }
        else {}
        end
        { outputs: outputs }
      end

      instance = start_and_classify(decision: "fix", reason: "real bug", inputs: phase1_inputs)

      expect(instance.state).to eq("completed")
      step_states = instance.steps.pluck(:step_id, :state).to_h
      expect(step_states["pre-dispatch-gate"]).to eq("completed")
      expect(step_states["create-fix-worktree"]).to eq("skipped")
      expect(step_states["run-swarm"]).to eq("skipped")
      expect(step_states["push-and-create-pr"]).to eq("skipped")
    end
  end

  describe "Phase 2 — dispatch without push" do
    it "runs up to safety-gate but skips push-and-create-pr" do
      instance = start_and_classify(decision: "fix", reason: "real bug")

      expect(instance.state).to eq("completed")
      step_states = instance.steps.pluck(:step_id, :state).to_h
      expect(step_states["pre-dispatch-gate"]).to eq("completed")
      expect(step_states["create-fix-worktree"]).to eq("completed")
      expect(step_states["run-swarm"]).to eq("completed")
      expect(step_states["safety-gate"]).to eq("completed")
      expect(step_states["push-and-create-pr"]).to eq("skipped")
      expect(step_states["notify-team"]).to eq("completed")
    end
  end

  describe "Phase 3 — full PR path" do
    let(:phase3_inputs) { base_inputs.merge("phase" => "3") }

    it "completes all steps including push-and-create-pr" do
      instance = start_and_classify(decision: "fix", reason: "real bug", inputs: phase3_inputs)

      expect(instance.state).to eq("completed")
      step_states = instance.steps.pluck(:step_id, :state).to_h
      expect(step_states["push-and-create-pr"]).to eq("completed")
      expect(step_states["notify-team"]).to eq("completed")
    end

    it "exposes pr_url from push-and-create-pr step" do
      instance = start_and_classify(decision: "fix", reason: "real bug", inputs: phase3_inputs)

      push_step = instance.steps.find_by!(step_id: "push-and-create-pr")
      expect(push_step.outputs["pr_url"]).to eq("https://github.com/coba-ai/coba/pull/99")
    end
  end

  describe "safety gate failure" do
    let(:safety_outputs) do
      { "files_changed" => 5, "additions" => 300, "critical_path_hit" => false,
        "gate_passed" => false, "gate_reason" => "too_many_files" }
    end

    it "skips push-and-create-pr when safety gate fails" do
      phase3_inputs = base_inputs.merge("phase" => "3")
      instance = start_and_classify(decision: "fix", reason: "real bug", inputs: phase3_inputs)

      expect(instance.state).to eq("completed")
      step_states = instance.steps.pluck(:step_id, :state).to_h
      expect(step_states["safety-gate"]).to eq("completed")
      expect(step_states["push-and-create-pr"]).to eq("skipped")
    end
  end

  describe "swarm returns no commit" do
    let(:swarm_outputs) { { "swarm_exit_code" => 0, "diff_summary" => "", "committed" => false } }

    it "skips safety-gate and push when swarm did not commit" do
      instance = start_and_classify(decision: "fix", reason: "real bug")

      step_states = instance.steps.pluck(:step_id, :state).to_h
      expect(step_states["run-swarm"]).to eq("completed")
      expect(step_states["safety-gate"]).to eq("skipped")
      expect(step_states["push-and-create-pr"]).to eq("skipped")
    end
  end

  describe "pre-dispatch ceiling hit (open PR exists)" do
    let(:gate_outputs) { { "gate_passed" => false, "gate_reason" => "open_pr_ceiling_hit" } }

    it "stops at pre-dispatch-gate" do
      instance = start_and_classify(decision: "fix", reason: "real bug")

      step_states = instance.steps.pluck(:step_id, :state).to_h
      expect(step_states["pre-dispatch-gate"]).to eq("completed")
      expect(step_states["create-fix-worktree"]).to eq("skipped")
    end
  end

  describe "API contract" do
    it "returns 404 for unknown process name" do
      get "/sop/appsignal-incident-fix-typo/schema"
      expect(response).to have_http_status(:not_found)
    end

    it "returns schema with expected step ids" do
      get "/sop/appsignal-incident-fix/schema"
      expect(response).to have_http_status(:ok)
      step_ids = json.dig(:process, :steps).map { |s| s[:id] }
      expect(step_ids).to include("classify-incident", "pre-dispatch-gate",
                                   "create-fix-worktree", "run-swarm",
                                   "safety-gate", "push-and-create-pr", "notify-team")
    end
  end
end
