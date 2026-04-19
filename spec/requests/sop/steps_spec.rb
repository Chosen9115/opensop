require 'rails_helper'

RSpec.describe "Sop steps", type: :request do
  let(:process_def) do
    # Small in-spec process: a form step followed by a notification step.
    {
      "opensop" => "0.1",
      "process" => {
        "name" => "steps-spec-proc",
        "version" => "1.0",
        "description" => "Steps spec",
        "inputs" => [ { "name" => "alpha", "type" => "string", "required" => true } ],
        "outputs" => [
          { "name" => "record", "from" => "steps.collect.outputs.record" }
        ],
        "steps" => [
          { "id" => "collect", "name" => "Collect", "type" => "form",
            "outputs" => [ { "name" => "record", "type" => "object" } ] },
          { "id" => "notify",  "name" => "Notify",  "type" => "notification" }
        ]
      }
    }
  end

  let!(:process) do
    create(:sop_process,
           name: "steps-spec-proc",
           version: "1.0",
           description: "Steps spec",
           definition: process_def)
  end

  let!(:instance) do
    Opensop::InstanceExecutor.start(process: process, inputs: { "alpha" => "ok" })
  end

  describe "GET /sop/:name/:id/steps" do
    it "returns the ordered steps" do
      get "/sop/steps-spec-proc/#{instance.id}/steps"

      expect(response).to have_http_status(:ok)
      ids = json[:steps].map { |s| s[:step_id] }
      expect(ids).to eq(%w[collect notify])
    end
  end

  describe "POST /sop/:name/:id/steps/:step_id/submit" do
    it "completes the step and advances the instance" do
      post "/sop/steps-spec-proc/#{instance.id}/steps/collect/submit",
           params: { outputs: { "record" => { "legal_name" => "Acme" } } }

      expect(response).to have_http_status(:ok)
      expect(json.dig(:step, :state)).to eq("completed")
      expect(json.dig(:instance, :state)).to eq("completed")
    end

    it "returns 422 when the step is not in a submittable state" do
      post "/sop/steps-spec-proc/#{instance.id}/steps/notify/submit",
           params: { outputs: {} }

      expect(response.status).to eq(422)
      expect(json[:error]).to eq("step_not_submittable")
    end
  end
end
