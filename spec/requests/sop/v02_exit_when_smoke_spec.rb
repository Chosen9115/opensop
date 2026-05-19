require "rails_helper"

RSpec.describe "v0.2 exit_when smoke end-to-end", type: :request do
  before do
    Opensop::Registry.load_file(
      Rails.root.join("processes/v02-smoke-exit-when.sop.yaml")
    )
  end

  it "short-circuits the process and writes literal exit_outputs when the gate predicate is true" do
    post "/sop/v02-smoke-exit-when/start",
         params: { inputs: { score: 0.3 } },
         as: :json

    expect(response).to have_http_status(:created).or have_http_status(:ok)

    body = JSON.parse(response.body)
    instance = Sop::Instance.find(body.fetch("id"))

    aggregate_failures do
      expect(instance.state).to eq("completed")

      # exit_outputs are merged literally into instance.outputs.
      expect(instance.outputs).to include(
        "outcome"       => "rejected_low_score",
        "stage_reached" => "gate"
      )

      # Gate ran; downstream steps still exist as `pending` rows (the engine
      # creates one row per declared step at start) but never advanced.
      gate     = instance.steps.find_by!(step_id: "gate")
      enrich   = instance.steps.find_by!(step_id: "enrich")
      finalize = instance.steps.find_by!(step_id: "finalize")

      expect(gate.state).to eq("completed")
      expect(enrich.state).to eq("pending")
      expect(finalize.state).to eq("pending")

      # The early-exit event carries the originating step_id and the literal
      # exit_outputs payload that was merged into the instance.
      event = instance.events.find_by(event_type: "instance.exited_early")
      expect(event).to be_present
      expect(event.data).to include("step_id" => "gate")
      expect(event.data["exit_outputs"]).to include(
        "outcome"       => "rejected_low_score",
        "stage_reached" => "gate"
      )
    end
  end

  it "runs every step to completion when the gate predicate is false" do
    post "/sop/v02-smoke-exit-when/start",
         params: { inputs: { score: 0.9 } },
         as: :json

    expect(response).to have_http_status(:created).or have_http_status(:ok)

    body = JSON.parse(response.body)
    instance = Sop::Instance.find(body.fetch("id"))

    aggregate_failures do
      expect(instance.state).to eq("completed")
      expect(instance.outputs).to include(
        "outcome"       => "passed",
        "stage_reached" => "finalize"
      )

      gate     = instance.steps.find_by!(step_id: "gate")
      enrich   = instance.steps.find_by!(step_id: "enrich")
      finalize = instance.steps.find_by!(step_id: "finalize")

      expect(gate.state).to eq("completed")
      expect(enrich.state).to eq("completed")
      expect(finalize.state).to eq("completed")

      # No exit event in the happy path.
      expect(instance.events.where(event_type: "instance.exited_early"))
        .not_to exist
    end
  end
end
