# frozen_string_literal: true

require "rails_helper"

# Request spec for Ui::InstancesController#show
#
# Covers the collapsible-JSON behavior in KeyValueListComponent rendered
# from the instance show page: complex (Hash/Array) inputs and outputs are
# wrapped in a <details> element that is collapsed by default.
RSpec.describe "Ui::Instances", type: :request do
  before do
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
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
end
