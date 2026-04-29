require "rails_helper"

RSpec.describe "POST /sop/processes/register", type: :request do
  let(:valid_yaml) do
    <<~YAML
      opensop: "0.1"

      process:
        name: smoke-register
        version: "1.0"
        description: "Smoke test process for register endpoint"
        owner: test-suite

        trigger:
          type: api

        inputs:
          - name: message
            type: string
            required: true

        outputs:
          - name: echoed
            type: string
            from: steps.echo.outputs.echoed

        steps:
          - id: echo
            name: "Echo message"
            type: automated
            inputs:
              - name: message
                from: process.inputs.message
            outputs:
              - name: echoed
                type: string
    YAML
  end

  describe "happy path" do
    it "registers a new process and returns 201" do
      post "/sop/processes/register", params: { yaml: valid_yaml }

      expect(response).to have_http_status(:created)
      expect(json[:name]).to eq("smoke-register")
      expect(json[:version]).to eq("1.0")
      expect(json[:steps]).to eq(["echo"])
      expect(json[:status]).to eq("active")
    end

    it "is idempotent — re-registering the same YAML returns 200" do
      post "/sop/processes/register", params: { yaml: valid_yaml }
      post "/sop/processes/register", params: { yaml: valid_yaml }

      expect(response).to have_http_status(:ok)
      expect(Sop::Process.where(name: "smoke-register").count).to eq(1)
    end

    it "upserts when definition changes" do
      post "/sop/processes/register", params: { yaml: valid_yaml }

      updated = valid_yaml.sub('description: "Smoke test process for register endpoint"',
                               'description: "Updated description"')
      post "/sop/processes/register", params: { yaml: updated }

      expect(response).to have_http_status(:created)
      expect(Sop::Process.find_by!(name: "smoke-register").description).to eq("Updated description")
    end

    it "accepts raw YAML as request body" do
      post "/sop/processes/register",
           params: valid_yaml,
           headers: { "Content-Type" => "application/x-yaml", "RAW_POST_DATA" => valid_yaml }

      expect(response).to have_http_status(:created)
      expect(json[:name]).to eq("smoke-register")
    end
  end

  describe "validation errors" do
    it "returns 422 when yaml param is missing" do
      post "/sop/processes/register", params: {}

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json[:error]).to eq("missing_yaml")
    end

    it "returns 422 for invalid YAML structure" do
      post "/sop/processes/register", params: { yaml: "not: valid: opensop: yaml" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json[:error]).to eq("invalid_definition")
    end

    it "returns 422 when required process fields are missing" do
      broken = <<~YAML
        opensop: "0.1"
        process:
          version: "1.0"
      YAML

      post "/sop/processes/register", params: { yaml: broken }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json[:error]).to eq("invalid_definition")
    end
  end

  describe "the registered process is immediately usable" do
    it "can start an instance after registration" do
      post "/sop/processes/register", params: { yaml: valid_yaml }
      expect(response).to have_http_status(:created)

      allow_any_instance_of(Opensop::StepExecutors::Automated).to receive(:call) do |_executor, step, _instance, _defn|
        { outputs: { "echoed" => step.inputs["message"] } }
      end

      post "/sop/smoke-register/start", params: { inputs: { "message" => "hello" } }
      expect(response).to have_http_status(:created)
      expect(json[:state]).to be_in(%w[running completed])
    end
  end
end
