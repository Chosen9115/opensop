# frozen_string_literal: true

require "rails_helper"

# Request spec for Ui::ProcessesController
#
# Covers:
#   1. Index hides older versions — only latest per name is shown
#   2. Index shows total runs, not just in-flight count
#   3. Trigger-run happy path — POST /processes/:name/runs → redirect to instance
#   4. Trigger-run invalid inputs — redirect back with flash alert, no instance created
#   5. Show page version dropdown — prior versions linked when >1 version exists
RSpec.describe "Ui::Processes", type: :request do
  before do
    sign_in_via_magic_link(create(:user))
  end

  # ---------------------------------------------------------------------------
  # Fix #1 — Index hides older versions
  # ---------------------------------------------------------------------------
  describe "GET /processes (index)" do
    context "when a process has multiple active versions" do
      let!(:proc_v1) do
        create(:sop_process,
               name: "close-of-day",
               version: "1.0",
               status: "active",
               definition: {
                 "opensop" => "0.1",
                 "process" => { "name" => "close-of-day", "version" => "1.0", "steps" => [] }
               })
      end
      let!(:proc_v11) do
        create(:sop_process,
               name: "close-of-day",
               version: "1.1",
               status: "active",
               definition: {
                 "opensop" => "0.1",
                 "process" => { "name" => "close-of-day", "version" => "1.1", "steps" => [] }
               })
      end

      it "shows only the latest version in the list" do
        get "/processes"

        expect(response).to have_http_status(:ok)
        # v1.1 version badge present
        expect(response.body).to include("v1.1")
      end

      it "does NOT show the old version as a separate row" do
        get "/processes"

        # v1.0 should NOT appear as a standalone version badge in the list
        # (it still exists in the DB but should not be a separate row)
        # The body may mention v1.0 in the prior-versions affordance,
        # but should NOT render it as a primary row entry with its own link.
        # We count occurrences: the only mention of v1.0 would be inside the
        # prior-versions tooltip/title, not as a standalone row version badge.
        expect(response.body).not_to match(/font-mono[^>]*>v1\.0</)
      end

      it "shows a prior versions affordance" do
        get "/processes"

        expect(response.body).to include("1 prior version")
      end
    end

    context "when each process has only one version" do
      let!(:proc_a) { create(:sop_process, name: "alpha-process", version: "1.0", status: "active") }
      let!(:proc_b) { create(:sop_process, name: "beta-process", version: "2.0", status: "active") }

      it "shows all processes with no prior-versions affordance" do
        get "/processes"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("alpha-process")
        expect(response.body).to include("beta-process")
        expect(response.body).not_to include("prior version")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Fix #2 — Index shows total runs not just in-flight
  # ---------------------------------------------------------------------------
  describe "GET /processes — run count" do
    let!(:my_process) do
      create(:sop_process,
             name: "billing-run",
             version: "1.0",
             status: "active",
             definition: {
               "opensop" => "0.1",
               "process" => { "name" => "billing-run", "version" => "1.0", "steps" => [] }
             })
    end

    context "when instances exist in mixed states" do
      before do
        create(:sop_instance, process: my_process, process_name: "billing-run", state: "completed")
        create(:sop_instance, process: my_process, process_name: "billing-run", state: "completed")
        create(:sop_instance, process: my_process, process_name: "billing-run", state: "pending")
      end

      it "shows a total run count of 3 (not 0 or 1)" do
        get "/processes"

        expect(response).to have_http_status(:ok)
        # The total_runs number should appear in the runs column.
        # We look for "3" near the "runs" label.
        expect(response.body).to match(/>\s*3\s*</)
      end
    end

    context "when all instances are completed (in-flight = 0)" do
      before do
        create(:sop_instance, process: my_process, process_name: "billing-run", state: "completed")
        create(:sop_instance, process: my_process, process_name: "billing-run", state: "completed")
      end

      it "shows total=2 without an in-flight row annotation" do
        get "/processes"

        expect(response.body).to match(/>\s*2\s*</)
        # The per-row in-flight annotation should not appear when in_flight=0.
        # We check that the text "· N in flight" annotation doesn't appear
        # (the global summary bar uses a different i18n key "in_flight_count").
        expect(response.body).not_to match(/in_flight_label|>\s*·\s*\d+\s*in flight\s*</)
      end
    end

    context "when there are in-flight instances" do
      before do
        create(:sop_instance, process: my_process, process_name: "billing-run", state: "completed")
        create(:sop_instance, process: my_process, process_name: "billing-run", state: "running")
      end

      it "shows the in-flight annotation" do
        get "/processes"

        expect(response.body).to include("in flight")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Fix #3 — Trigger run
  # ---------------------------------------------------------------------------
  describe "POST /processes/:name/runs" do
    let(:process_def_with_inputs) do
      {
        "opensop" => "0.1",
        "process" => {
          "name" => "onboard-employee",
          "version" => "1.0",
          "inputs" => [
            { "name" => "employee_name", "type" => "string", "required" => true },
            { "name" => "start_date",    "type" => "string", "required" => false }
          ],
          "steps" => []
        }
      }
    end

    let!(:my_process) do
      create(:sop_process,
             name: "onboard-employee",
             version: "1.0",
             status: "active",
             definition: process_def_with_inputs)
    end

    context "with valid inputs (happy path)" do
      it "creates a new instance in pending state and redirects to it" do
        expect {
          post "/processes/onboard-employee/runs",
               params: { inputs: { employee_name: "Alice" } }
        }.to change(Sop::Instance, :count).by(1)

        expect(response).to be_redirect

        instance = Sop::Instance.last
        follow_redirect!

        expect(request.path).to eq("/instances/#{instance.id}")
        expect(instance.inputs["employee_name"]).to eq("Alice")
        # Instance starts as pending then may immediately advance to running
        # (no real async executor in test), but it must have been created.
        expect(%w[ pending running completed ]).to include(instance.state)
      end
    end

    context "with missing required inputs (invalid path)" do
      it "does NOT create an instance and redirects back with a flash alert" do
        expect {
          post "/processes/onboard-employee/runs",
               params: { inputs: {} }
        }.not_to change(Sop::Instance, :count)

        expect(response).to be_redirect
        follow_redirect!

        expect(request.path).to eq("/processes/onboard-employee")
        expect(response.body).to include("Invalid inputs")
      end
    end

    context "when process does not exist" do
      it "returns 404 (RecordNotFound is rescued by Ui::ApplicationController)" do
        post "/processes/nonexistent/runs",
             params: { inputs: {} }

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Fix #1 (show) — prior versions dropdown on the show page
  # ---------------------------------------------------------------------------
  describe "GET /processes/:name (show)" do
    context "when multiple versions exist" do
      let!(:proc_v1) do
        create(:sop_process,
               name: "close-of-day",
               version: "1.0",
               status: "active",
               definition: {
                 "opensop" => "0.1",
                 "process" => { "name" => "close-of-day", "version" => "1.0", "steps" => [] }
               })
      end
      let!(:proc_v2) do
        create(:sop_process,
               name: "close-of-day",
               version: "2.0",
               status: "active",
               definition: {
                 "opensop" => "0.1",
                 "process" => { "name" => "close-of-day", "version" => "2.0", "steps" => [] }
               })
      end

      it "shows the latest version by default" do
        get "/processes/close-of-day"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("v2.0")
      end

      it "renders a link to the older version" do
        get "/processes/close-of-day"

        expect(response.body).to include("v1.0")
        expect(response.body).to include("Other versions")
      end

      it "shows the older version when ?version= is specified" do
        get "/processes/close-of-day?version=1.0"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("v1.0")
      end
    end

    context "when only one version exists" do
      let!(:proc_only) do
        create(:sop_process,
               name: "solo-process",
               version: "1.0",
               status: "active",
               definition: {
                 "opensop" => "0.1",
                 "process" => { "name" => "solo-process", "version" => "1.0", "steps" => [] }
               })
      end

      it "does NOT render the other-versions section" do
        get "/processes/solo-process"

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("Other versions")
      end
    end
  end
end
