require "rails_helper"

RSpec.describe "v0.2 llm step end-to-end", type: :request do
  before do
    # Load the smoke process into the test DB
    Opensop::Registry.load_file(
      Rails.root.join("spec/fixtures/processes/v02-smoke-llm.sop.yaml")
    )

    # Swap in the stub provider — no network calls
    Opensop::StepExecutors::Llm.provider_resolver = ->(model) {
      Opensop::LlmProviders::TestStub.new(
        canned_response: {
          "intent" => "question",
          "confidence" => 0.93,
          "rationale" => "ends with question mark"
        }
      )
    }
  end

  after { Opensop::StepExecutors::Llm.reset_provider_resolver! }

  it "starts an instance, runs the llm step, populates outputs, records the LlmCall" do
    post "/sop/v02-smoke-llm/start",
         params: { inputs: { user_message: "What time does support close?" } },
         as: :json

    expect(response).to have_http_status(:created).or have_http_status(:ok)

    body = JSON.parse(response.body)
    instance_id = body.fetch("id")

    # Engine runs synchronously in v0.2; verify final state.
    instance = Sop::Instance.find(instance_id)
    expect(instance.state).to eq("completed")
    expect(instance.outputs).to include("intent" => "question", "confidence" => 0.93)

    classify_step = instance.steps.find_by(step_id: "classify")
    expect(classify_step.state).to eq("completed")
    expect(classify_step.outputs).to include("intent" => "question")

    expect(classify_step.llm_calls.count).to eq(1)
    call = classify_step.llm_calls.first
    expect(call.status).to eq("succeeded")
    expect(call.input_tokens).to eq(1)
    expect(call.output_tokens).to eq(1)
    expect(call.model).to eq("claude-sonnet-4-7")
  end
end
