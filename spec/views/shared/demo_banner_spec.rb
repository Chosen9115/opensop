# frozen_string_literal: true

require "rails_helper"

RSpec.describe "shared/_demo_banner", type: :view do
  around do |example|
    original = ENV["DEMO_MODE"]
    example.run
  ensure
    original.nil? ? ENV.delete("DEMO_MODE") : ENV["DEMO_MODE"] = original
  end

  context "when DEMO_MODE is on" do
    before { ENV["DEMO_MODE"] = "true" }

    it "renders the localized banner message" do
      render partial: "shared/demo_banner"
      # ERB HTML-encodes certain characters (e.g. apostrophe → &#39;).
      # Assert on the schedule string which has no special chars, and on
      # a unique fragment of the message that survives encoding.
      expect(rendered).to include(Opensop::DemoMode::RESET_SCHEDULE_HUMAN)
      expect(rendered).to include("Public demo")
    end

    it "includes a link to the GitHub repository" do
      render partial: "shared/demo_banner"
      expect(rendered).to include("https://github.com/Chosen9115/opensop")
    end

    it "renders non-empty HTML" do
      render partial: "shared/demo_banner"
      expect(rendered.strip).not_to be_empty
    end
  end

  context "when DEMO_MODE is off" do
    before { ENV.delete("DEMO_MODE") }

    it "renders to effectively empty content (no banner markup)" do
      render partial: "shared/demo_banner"
      # The partial is wrapped in <% if Opensop::DemoMode.enabled? %> — when
      # false, only whitespace is emitted.
      expect(rendered.strip).to be_empty
    end
  end
end
