require "rails_helper"

# Request spec for the JSON metrics endpoint.
#
# NOTE: Until the integration agent wires
#   `get "/metrics", to: "metrics#index", as: :metrics`
# inside the existing `:sop` scope in `config/routes/sop.rb`, this spec
# stubs the route directly so the controller + service can be exercised
# in isolation. Once the real route ships, removing the `with_routing`
# block at the top should leave the example bodies passing unchanged.
RSpec.describe "Sop::Metrics", type: :request do
  # ApplicationController warns once about an unset token via class var —
  # reset so we don't leak state across the auth examples.
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

  # Route stub — mirrors the line the integration agent will add to
  # config/routes/sop.rb. Scoped to this spec only.
  around do |ex|
    Rails.application.routes.draw do
      scope :sop, as: :sop, module: :sop, defaults: { format: :json } do
        get "/metrics", to: "metrics#index", as: :metrics
      end
    end
    ex.run
  ensure
    Rails.application.reload_routes!
  end

  describe "GET /sop/metrics" do
    context "with no data" do
      before { ENV.delete("OPENSOP_API_TOKEN") }

      it "returns 200 and a JSON document with the documented shape" do
        get "/sop/metrics"

        expect(response).to have_http_status(:ok)

        expect(json).to include(:window_seconds, :totals, :per_process, :step_health)
        expect(json[:window_seconds]).to eq(86400)

        expect(json[:totals]).to include(
          :instances_started, :instances_completed, :instances_failed,
          :completion_rate, :avg_duration_seconds, :p95_duration_seconds
        )
        expect(json[:totals][:instances_started]).to eq(0)
        expect(json[:totals][:completion_rate]).to eq(0.0)

        expect(json[:per_process]).to eq([])

        expect(json[:step_health]).to include(
          :pending, :active, :completed, :failed, :skipped
        )
      end
    end

    context "with seeded instances" do
      before do
        ENV.delete("OPENSOP_API_TOKEN")

        process = create(:sop_process, name: "alpha", version: "1.0")
        create(:sop_instance,
               process: process, process_name: "alpha", process_version: "1.0",
               state: "completed",
               created_at: 2.hours.ago,
               started_at: 2.hours.ago,
               completed_at: 2.hours.ago + 60.seconds,
               updated_at: 2.hours.ago + 60.seconds)
        create(:sop_instance,
               process: process, process_name: "alpha", process_version: "1.0",
               state: "failed",
               created_at: 1.hour.ago,
               updated_at: 1.hour.ago + 10.seconds,
               completed_at: 1.hour.ago + 10.seconds)
      end

      it "returns aggregated totals and per_process rows" do
        get "/sop/metrics"

        expect(response).to have_http_status(:ok)
        expect(json[:totals][:instances_started]).to eq(2)
        expect(json[:totals][:instances_completed]).to eq(1)
        expect(json[:totals][:instances_failed]).to eq(1)
        expect(json[:totals][:completion_rate]).to be_within(0.001).of(0.5)

        expect(json[:per_process].size).to eq(1)
        row = json[:per_process].first
        expect(row[:process_name]).to eq("alpha")
        expect(row[:version]).to eq("1.0")
        expect(row[:started]).to eq(2)
        expect(row[:completed]).to eq(1)
        expect(row[:failed]).to eq(1)
      end
    end

    context "auth gate" do
      it "returns 401 when OPENSOP_API_TOKEN is set and no header is provided" do
        ENV["OPENSOP_API_TOKEN"] = "secret-metrics"

        get "/sop/metrics"

        expect(response).to have_http_status(:unauthorized)
        expect(json[:error]).to eq("unauthorized")
      end

      it "returns 200 when OPENSOP_API_TOKEN matches the provided header" do
        ENV["OPENSOP_API_TOKEN"] = "secret-metrics"

        get "/sop/metrics", headers: { "X-SOP-Token" => "secret-metrics" }

        expect(response).to have_http_status(:ok)
      end

      it "returns 401 when token mismatches" do
        ENV["OPENSOP_API_TOKEN"] = "secret-metrics"

        get "/sop/metrics", headers: { "X-SOP-Token" => "wrong" }

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
