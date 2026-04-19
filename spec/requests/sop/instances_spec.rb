require 'rails_helper'

RSpec.describe "Sop instances", type: :request do
  let(:valid_inputs) do
    {
      "company_name"   => "Acme",
      "contact_email"  => "ada@example.com",
      "country"        => "US",
      "source_channel" => "website"
    }
  end

  before { load_customer_onboarding! }

  describe "POST /sop/:name/start" do
    it "creates an instance and returns 201" do
      post "/sop/customer-onboarding/start", params: { inputs: valid_inputs }

      expect(response).to have_http_status(:created)
      expect(json[:state]).to be_in(%w[running pending])
      expect(json[:steps]).to be_a(Array)
      expect(json.dig(:process, :name)).to eq("customer-onboarding")
    end

    it "rejects missing required inputs with 422 invalid_inputs" do
      post "/sop/customer-onboarding/start", params: { inputs: { "company_name" => "Acme" } }

      expect(response.status).to eq(422)
      expect(json[:error]).to eq("invalid_inputs")
    end
  end

  describe "GET /sop/:name/:id" do
    it "returns 200 with instance details" do
      instance = Opensop::InstanceExecutor.start(
        process: Sop::Process.find_by!(name: "customer-onboarding"),
        inputs: valid_inputs
      )

      get "/sop/customer-onboarding/#{instance.id}"

      expect(response).to have_http_status(:ok)
      expect(json[:id]).to eq(instance.id)
    end

    it "returns 404 when the instance does not exist" do
      get "/sop/customer-onboarding/00000000-0000-0000-0000-000000000000"

      expect(response).to have_http_status(:not_found)
      expect(json[:error]).to eq("not_found")
    end
  end

  describe "GET /sop/instances" do
    before do
      process = Sop::Process.find_by!(name: "customer-onboarding")
      2.times { Opensop::InstanceExecutor.start(process: process, inputs: valid_inputs) }
    end

    it "lists instances" do
      get "/sop/instances"

      expect(response).to have_http_status(:ok)
      expect(json[:instances].length).to be >= 2
      expect(json[:total]).to be >= 2
    end

    it "filters by state" do
      get "/sop/instances", params: { state: "running" }

      expect(response).to have_http_status(:ok)
      expect(json[:instances].map { |i| i[:state] }.uniq).to all(eq("running"))
    end
  end

  describe "POST /sop/:name/:id/cancel" do
    it "cancels an active instance" do
      instance = Opensop::InstanceExecutor.start(
        process: Sop::Process.find_by!(name: "customer-onboarding"),
        inputs: valid_inputs
      )

      post "/sop/customer-onboarding/#{instance.id}/cancel", params: { reason: "user abandoned" }

      expect(response).to have_http_status(:ok)
      expect(json[:state]).to eq("cancelled")
    end
  end
end
