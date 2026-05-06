# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ui::Demo::Home", type: :request do
  context "with DEMO_MODE enabled" do
    around do |ex|
      ENV["DEMO_MODE"] = "true"
      ex.run
      ENV.delete("DEMO_MODE")
    end

    it "renders the demo homepage at /" do
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("OpenSOP").or include("opensop")
    end

    it "exposes the api token in the page" do
      get "/"
      expect(response.body).to include(Opensop::DemoMode.api_token)
    end

    it "includes the demo banner" do
      get "/"
      expect(response.body).to include("daily at 3:00 UTC")
    end
  end

  context "with DEMO_MODE disabled" do
    around do |ex|
      ENV.delete("DEMO_MODE")
      ex.run
    end

    it "renders the dashboard at /" do
      get "/"
      expect(response).to have_http_status(:ok)
    end
  end
end
