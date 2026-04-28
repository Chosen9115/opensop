require "rails_helper"

RSpec.describe "v0.2 loop + llm smoke end-to-end", type: :request do
  # Round-robin classification responses so the three iterations produce
  # visibly different outputs. The TestStub re-renders this hash on every
  # `.call` — we wrap it in a counter-driven resolver below so each
  # iteration sees its own canned response.
  CANNED_CLASSIFICATIONS = [
    { "intent" => "question",  "confidence" => 0.91 },
    { "intent" => "task",      "confidence" => 0.88 },
    { "intent" => "complaint", "confidence" => 0.95 }
  ].freeze

  before do
    Opensop::Registry.load_file(
      Rails.root.join("processes/v02-smoke-loop-llm.sop.yaml")
    )

    # Each call to provider_resolver.(model) returns a fresh TestStub bound
    # to the next canned response, so the LLM body sees different content
    # per iteration. The loop executor fetches the resolver once per body
    # step invocation, which means once per iteration.
    @counter = 0
    Opensop::StepExecutors::Llm.provider_resolver = ->(_model) {
      response = CANNED_CLASSIFICATIONS[@counter % CANNED_CLASSIFICATIONS.size]
      @counter += 1
      Opensop::LlmProviders::TestStub.new(canned_response: response)
    }
  end

  after { Opensop::StepExecutors::Llm.reset_provider_resolver! }

  it "fans the llm body across each message and aggregates the per-iteration classifications" do
    post "/sop/v02-smoke-loop-llm/start",
         params: {
           inputs: {
             messages: [
               { id: "m1", text: "Hi?" },
               { id: "m2", text: "Do X" },
               { id: "m3", text: "Bad!" }
             ]
           }
         },
         as: :json

    expect(response).to have_http_status(:created).or have_http_status(:ok)

    body = JSON.parse(response.body)
    instance = Sop::Instance.find(body.fetch("id"))

    aggregate_failures do
      expect(instance.state).to eq("completed")

      # Aggregated loop output flows up to process.outputs.classifications
      # via process.outputs[from: steps.classify-each.outputs.classifications].
      classifications = instance.outputs["classifications"]
      expect(classifications).to be_an(Array)
      expect(classifications.length).to eq(3)
      classifications.each do |c|
        expect(c).to include("intent", "confidence")
      end
      expect(classifications.map { |c| c["intent"] })
        .to eq(%w[question task complaint])

      # Loop step: 3 StepIteration rows, each carrying the bound `msg` and
      # numeric `index` in iteration_inputs.
      loop_step = instance.steps.find_by!(step_id: "classify-each")
      iterations = loop_step.iterations.ordered
      expect(iterations.size).to eq(3)
      iterations.each_with_index do |iter, i|
        expect(iter.iteration_inputs).to include("index" => i)
        expect(iter.iteration_inputs).to have_key("msg")
        expect(iter.iteration_inputs["msg"]).to include("id", "text")
      end

      # Three LlmCall rows — one per body-step execution.
      llm_calls = Sop::LlmCall.joins(:step).where(sop_steps: { instance_id: instance.id })
      expect(llm_calls.count).to eq(3)
      expect(llm_calls.pluck(:status).uniq).to eq([ "succeeded" ])
      expect(llm_calls.pluck(:model).uniq).to eq([ "claude-sonnet-4-7" ])
    end
  end
end
