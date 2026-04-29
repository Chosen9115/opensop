require "rails_helper"

# Request spec for the Metrics admin index page.
#
# NOTE: The route `GET /metrics -> ui/metrics#index` is added by the
# integration agent in `config/routes/ui.rb`. Until that ships these
# specs will fail with a routing error ("No route matches GET /metrics") —
# that is expected. Once the integration agent wires the route, this file
# should pass without modification.
RSpec.describe "Ui::Metrics", type: :request do
  before do
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
  end

  describe "GET /metrics" do
    context "when there is no data" do
      it "responds with 200 and renders the page header" do
        get "/metrics"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Metrics")
        expect(response.body).to include("Process throughput and success")
      end

      it "renders the empty state for the per-process table" do
        get "/metrics"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No process activity in the last 24h")
      end

      it "still renders zero-valued tiles" do
        get "/metrics"

        # Hero tiles use the 28px font-mono class.
        expect(response.body).to match(/text-\[28px\][^>]*>\s*0\s*</)
      end
    end

    context "when instances exist within the 24h window" do
      let!(:process) { create(:sop_process, name: "alpha", version: "1.0") }

      before do
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
        create(:sop_instance,
               process: process, process_name: "alpha", process_version: "1.0",
               state: "running",
               created_at: 30.minutes.ago,
               started_at: 30.minutes.ago,
               updated_at: 30.minutes.ago)
      end

      it "responds with 200 and renders the per-process table with the row" do
        get "/metrics"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Per-process throughput")
        expect(response.body).to include("alpha")
        expect(response.body).to include("v1.0")
      end

      it "renders the duration card with avg and p95 values" do
        get "/metrics"

        expect(response.body).to include("Average")
        expect(response.body).to include("P95")
      end

      it "renders the step health row with the five state buckets" do
        get "/metrics"

        expect(response.body).to include("Step health")
        %w[Pending Active Completed Failed Skipped].each do |label|
          expect(response.body).to include(label)
        end
      end
    end

    context "when an underlying table is unavailable" do
      it "still renders the page with zero values" do
        allow(Sop::Instance).to receive(:where)
          .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))

        get "/metrics"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Metrics")
      end
    end
  end
end
