# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DemoReadOnly", type: :request do
  context "with DEMO_MODE enabled" do
    around do |example|
      ENV["DEMO_MODE"] = "true"
      example.run
    ensure
      ENV["DEMO_MODE"] = nil
    end

    it "blocks POST /sop/processes/register with 403" do
      post "/sop/processes/register",
           params: { name: "x" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("demo_read_only")
    end

    it "allows GET /sop/ (discovery)" do
      get "/sop/"
      expect(response).to have_http_status(:ok).or have_http_status(:unauthorized)
      # Even unauthorized is fine — the point is that DemoReadOnly didn't intercept.
    end
  end

  context "with DEMO_MODE disabled" do
    it "does NOT add the demo guard" do
      post "/sop/processes/register"
      # Expect anything OTHER than 403-with-demo_read_only-error.
      if response.status == 403
        body = JSON.parse(response.body) rescue {}
        expect(body["error"]).not_to eq("demo_read_only")
      end
    end
  end
end
