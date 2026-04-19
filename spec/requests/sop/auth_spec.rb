require 'rails_helper'

RSpec.describe "Sop API auth", type: :request do
  # ApplicationController caches "we warned about unset token" in a class var
  # across examples. Reset it so our unset-path spec can observe the warning.
  before { Sop::ApplicationController.class_variable_set(:@@unauth_warned, false) }

  around do |ex|
    original = ENV["OPENSOP_API_TOKEN"]
    ex.run
  ensure
    if original.nil?
      ENV.delete("OPENSOP_API_TOKEN")
    else
      ENV["OPENSOP_API_TOKEN"] = original
    end
  end

  context "when OPENSOP_API_TOKEN is set" do
    before { ENV["OPENSOP_API_TOKEN"] = "secret-token" }

    it "returns 200 with a matching X-SOP-Token" do
      get "/sop/", headers: { "X-SOP-Token" => "secret-token" }
      expect(response).to have_http_status(:ok)
    end

    it "returns 401 with no token" do
      get "/sop/"
      expect(response).to have_http_status(:unauthorized)
      expect(json[:error]).to eq("unauthorized")
    end

    it "returns 401 with a wrong token" do
      get "/sop/", headers: { "X-SOP-Token" => "wrong" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "when OPENSOP_API_TOKEN is unset" do
    before { ENV.delete("OPENSOP_API_TOKEN") }

    it "allows requests through and logs a warning" do
      allow(Rails.logger).to receive(:warn)

      get "/sop/"

      expect(response).to have_http_status(:ok)
      expect(Rails.logger).to have_received(:warn).with(/OPENSOP_API_TOKEN not set/)
    end
  end
end
