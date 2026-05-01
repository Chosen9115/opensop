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

    it "returns 200" do
      get "/instances/#{instance.id}"

      expect(response).to have_http_status(:ok)
    end

    it "renders complex values inside <details> elements" do
      get "/instances/#{instance.id}"

      expect(response.body).to include("<details")
    end

    it "leaves the <details> elements collapsed by default" do
      get "/instances/#{instance.id}"

      # No <details> wrapper for inputs/outputs should ship with the
      # `open` attribute — they must be collapsed on first paint.
      doc = Nokogiri::HTML.fragment(response.body)
      details = doc.css("details")

      expect(details).not_to be_empty
      expect(details.any? { |d| d.attributes.key?("open") }).to be(false)
    end
  end
end
