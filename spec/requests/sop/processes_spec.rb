require 'rails_helper'

RSpec.describe "Sop processes schema", type: :request do
  describe "GET /sop/:name/schema" do
    it "returns 200 with the full definition" do
      load_customer_onboarding!

      get "/sop/customer-onboarding/schema"

      expect(response).to have_http_status(:ok)
      expect(json.dig(:process, :name)).to eq("customer-onboarding")
      expect(json[:opensop]).to eq("0.1")
    end

    it "returns 404 for an unknown process" do
      get "/sop/does-not-exist/schema"

      expect(response).to have_http_status(:not_found)
      expect(json[:error]).to eq("not_found")
    end

    it "supports filtering by version" do
      create(:sop_process, name: "multi-ver", version: "1.0",
             definition: {
               "opensop" => "0.1",
               "process" => { "name" => "multi-ver", "version" => "1.0", "steps" => [] }
             })
      create(:sop_process, name: "multi-ver", version: "2.0",
             definition: {
               "opensop" => "0.1",
               "process" => { "name" => "multi-ver", "version" => "2.0", "steps" => [] }
             })

      get "/sop/multi-ver/schema", params: { version: "1.0" }

      expect(response).to have_http_status(:ok)
      expect(json.dig(:process, :version)).to eq("1.0")
    end
  end
end
