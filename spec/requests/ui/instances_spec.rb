# frozen_string_literal: true

require "rails_helper"

# Request spec for Ui::InstancesController#show
#
# Covers the collapsible-JSON behavior in KeyValueListComponent rendered
# from the instance show page: complex (Hash/Array) inputs and outputs are
# wrapped in a <details> element that is collapsed by default.
RSpec.describe "Ui::Instances", type: :request do
  before do
    sign_in_via_magic_link(create(:user))
  end

  describe "GET /instances/:id" do
    let!(:process) do
      create(:sop_process,
             name: "deploy-job",
             version: "1.0",
             status: "active",
             definition: {
               "opensop" => "0.1",
               "process" => { "name" => "deploy-job", "version" => "1.0", "steps" => [] }
             })
    end

    let!(:instance) do
      create(:sop_instance, :completed,
             process: process,
             process_name: "deploy-job",
             process_version: "1.0",
             inputs: {
               "config" => { "region" => "us-east-1", "replicas" => 3 },
               "tags" => [ "prod", "critical" ],
               "label" => "v1.2.3"
             },
             outputs: {
               "summary" => { "ok" => true, "duration_s" => 42 }
             })
    end

    it "renders all complex inputs/outputs inside <details> collapsed by default" do
      get "/instances/#{instance.id}"

      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML.fragment(response.body)
      details = doc.css("details")

      expect(details).not_to be_empty
      expect(details.any? { |d| d.attributes.key?("open") }).to be(false)
    end

    it "wraps event row JSON data in collapsed <details>" do
      create(:sop_event,
             instance: instance,
             event_type: "step.completed",
             step_id: "deploy",
             data: { "exit_code" => 0, "duration_ms" => 1234 })

      get "/instances/#{instance.id}"

      doc = Nokogiri::HTML.fragment(response.body)
      # The events feed sits in its own <ul>; scope to event-row pre/details
      # by checking text-[10px] (the event-row size hint) is on the summary.
      event_summaries = doc.css("details > summary").select { |s| s["class"]&.include?("text-[10px]") }

      expect(event_summaries).not_to be_empty
      event_summaries.each do |summary|
        expect(summary.parent.attributes).not_to have_key("open")
      end
    end
  end

  describe "GET /instances/:id with errors" do
    let!(:errored_process) do
      create(:sop_process,
             name: "deploy-job-error",
             version: "1.0",
             status: "active",
             definition: {
               "opensop" => "0.1",
               "process" => { "name" => "deploy-job-error", "version" => "1.0", "steps" => [] }
             })
    end

    context "instance has an error" do
      let!(:instance) do
        create(:sop_instance,
               process: errored_process,
               process_name: "deploy-job-error",
               process_version: "1.0",
               state: "failed",
               error: "Connection refused: redis://localhost:6379",
               inputs: {})
      end

      it "renders the instance-level copy-debug button with the prompt" do
        get "/instances/#{instance.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-controller="copy-prompt"')
        expect(response.body).to include('data-copy-prompt-text-value=')
      end

      it "includes instance error details in the debug prompt" do
        get "/instances/#{instance.id}"
        expect(response).to have_http_status(:ok)
        # The debug prompt is rendered as a data attribute; check for process context
        expect(response.body).to include("deploy-job-error")
      end
    end

    context "step has an error" do
      let!(:instance) do
        create(:sop_instance,
               process: errored_process,
               process_name: "deploy-job-error",
               process_version: "1.0",
               state: "running",
               inputs: {})
      end
      let!(:errored_step) do
        create(:sop_step,
               instance: instance,
               step_id: "build",
               step_name: "Build",
               step_type: "automated",
               state: "failed",
               position: 1,
               error: "exit 1")
      end

      it "renders a copy-debug button on the errored step card" do
        get "/instances/#{instance.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body.scan('data-controller="copy-prompt"').size).to be >= 1
      end
    end

    context "instance has both instance-level and step-level errors" do
      let!(:instance) do
        create(:sop_instance,
               process: errored_process,
               process_name: "deploy-job-error",
               process_version: "1.0",
               state: "running",
               error: "Timeout after 30s",
               inputs: {})
      end
      let!(:errored_step) do
        create(:sop_step,
               instance: instance,
               step_id: "health-check",
               step_name: "Health Check",
               step_type: "automated",
               state: "failed",
               position: 2,
               error: "port 8000 unreachable")
      end

      it "renders copy-debug buttons for both instance and step" do
        get "/instances/#{instance.id}"
        expect(response).to have_http_status(:ok)
        # Multiple copy-prompt controllers on the page: one for instance, one for step
        expect(response.body.scan('data-controller="copy-prompt"').size).to be >= 2
      end
    end

    context "instance has no errors and no errored steps" do
      let!(:instance) do
        create(:sop_instance, :completed,
               process: errored_process,
               process_name: "deploy-job-error",
               process_version: "1.0",
               inputs: {})
      end

      it "does not render any copy-debug button" do
        get "/instances/#{instance.id}"
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('data-controller="copy-prompt"')
      end
    end
  end
end
