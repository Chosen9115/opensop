require 'rails_helper'

RSpec.describe "Sop discovery", type: :request do
  describe "GET /sop/" do
    it "returns 200 and lists the customer-onboarding process" do
      load_customer_onboarding!

      get "/sop/"

      expect(response).to have_http_status(:ok)
      expect(json).to have_key(:processes)
      names = json[:processes].map { |p| p[:name] }
      expect(names).to include("customer-onboarding")
    end

    it "only lists active processes" do
      create(:sop_process, name: "live-one",     version: "1.0", status: "active")
      create(:sop_process, name: "dead-one",     version: "1.0", status: "deprecated")
      create(:sop_process, name: "archived-one", version: "1.0", status: "archived")

      get "/sop/"

      names = json[:processes].map { |p| p[:name] }
      expect(names).to include("live-one")
      expect(names).not_to include("dead-one", "archived-one")
    end

    it "dedupes by name, returning the latest version" do
      create(:sop_process, name: "multi-ver", version: "1.0")
      create(:sop_process, name: "multi-ver", version: "2.0")

      get "/sop/"

      match = json[:processes].detect { |p| p[:name] == "multi-ver" }
      expect(match).not_to be_nil
      expect(match[:version]).to eq("2.0")
    end
  end
end
