require "rails_helper"

# Request spec for the Schedule admin index page (Tier 3).
#
# Covers:
#   * page header + zero-tile rendering when there are no schedules
#   * empty-state copy when no rows exist
#   * table rendering with status + state pills when rows exist
#   * hero tile counts (active / due_now / failures_24h)
#   * graceful degradation when the sop_schedules table isn't migrated
RSpec.describe "Ui::Schedules", type: :request do
  before do
    sign_in_via_magic_link(create(:user))
  end

  describe "GET /schedule" do
    context "when there are no schedules" do
      it "responds with 200 and renders the page header" do
        get "/schedule"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Schedule")
      end

      it "renders the empty state copy" do
        get "/schedule"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("No schedules yet")
      end

      it "still renders zero-valued hero tiles" do
        get "/schedule"

        # Hero tile labels render.
        expect(response.body).to include("Active schedules")
        expect(response.body).to include("Due now")
        expect(response.body).to include("Failures (24h)")
        # Hero tiles use the 28px font-mono class with zeros.
        expect(response.body).to match(/text-\[28px\][^>]*>\s*0\s*</)
      end
    end

    context "when schedules exist" do
      let!(:enabled_success) do
        create(:sop_schedule,
               name: "Daily payroll",
               description: "Run payroll each weekday",
               process_name: "payroll_run",
               cron_expression: "0 9 * * 1-5",
               timezone: "UTC",
               enabled: true,
               last_status: "success",
               last_run_at: 2.hours.ago,
               next_run_at: 1.hour.from_now)
      end

      let!(:enabled_failed) do
        create(:sop_schedule,
               name: "Hourly sync",
               description: "Sync inventory hourly",
               process_name: "inventory_sync",
               cron_expression: "0 * * * *",
               timezone: "America/New_York",
               enabled: true,
               last_status: "failed",
               last_run_at: 30.minutes.ago,
               next_run_at: 30.minutes.from_now,
               failure_count: 1)
      end

      let!(:disabled_schedule) do
        create(:sop_schedule,
               name: "Quarterly close",
               description: "Run quarterly close",
               process_name: "quarterly_close",
               cron_expression: "0 0 1 1,4,7,10 *",
               timezone: "UTC",
               enabled: false,
               last_status: nil,
               last_run_at: nil,
               next_run_at: 30.days.from_now)
      end

      let!(:due_now_schedule) do
        create(:sop_schedule,
               name: "Overdue task",
               description: "This one is past due",
               process_name: "overdue",
               cron_expression: "*/5 * * * *",
               timezone: "UTC",
               enabled: true,
               last_status: nil,
               last_run_at: nil,
               next_run_at: 5.minutes.ago)
      end

      it "renders 200 and lists each schedule by name and process" do
        get "/schedule"

        expect(response).to have_http_status(:ok)

        expect(response.body).to include("Daily payroll")
        expect(response.body).to include("Hourly sync")
        expect(response.body).to include("Quarterly close")
        expect(response.body).to include("Overdue task")

        expect(response.body).to include("payroll_run")
        expect(response.body).to include("inventory_sync")
        expect(response.body).to include("quarterly_close")
      end

      it "renders cron expressions and timezones" do
        get "/schedule"

        expect(response.body).to include("0 9 * * 1-5")
        expect(response.body).to include("0 * * * *")
        expect(response.body).to include("UTC")
        expect(response.body).to include("America/New_York")
      end

      it "renders status pills for success / failed / none" do
        get "/schedule"

        expect(response.body).to include("success")
        expect(response.body).to include("failed")
      end

      it "renders state pills for enabled and disabled" do
        get "/schedule"

        expect(response.body).to include("enabled")
        expect(response.body).to include("disabled")
      end

      it "renders the active count tile (3 enabled out of 4)" do
        get "/schedule"

        # Active tile shows "3" — pull the active number near its label.
        expect(response.body).to match(/Active schedules.*?text-\[28px\][^>]*>\s*3\s*</m)
      end

      it "renders the due_now count tile (1 due)" do
        get "/schedule"

        expect(response.body).to match(/Due now.*?text-\[28px\][^>]*>\s*1\s*</m)
      end

      it "renders the failures_24h count tile (1 failed in last 24h)" do
        get "/schedule"

        expect(response.body).to match(/Failures \(24h\).*?text-\[28px\][^>]*>\s*1\s*</m)
      end
    end

    context "when the sop_schedules table is unavailable" do
      it "renders the unavailable empty state without erroring" do
        allow(Sop::Schedule).to receive(:order)
          .and_raise(ActiveRecord::StatementInvalid.new("relation does not exist"))

        get "/schedule"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Schedules table not yet migrated")
      end
    end
  end
end
