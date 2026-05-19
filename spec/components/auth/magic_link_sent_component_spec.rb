# frozen_string_literal: true

require "rails_helper"
require "view_component/test_helpers"

RSpec.describe Auth::MagicLinkSentComponent, type: :component do
  include ViewComponent::TestHelpers

  def vc_test_controller_class
    ActionController::Base
  end

  it "renders without errors" do
    expect { render_inline(described_class.new) }.not_to raise_error
  end

  it "renders the heading and body via i18n" do
    result = render_inline(described_class.new)

    expect(result.text).to include(I18n.t("opensop.auth.magic_link_sent.heading"))
    expect(result.text).to include(I18n.t("opensop.auth.magic_link_sent.body"))
  end

  it "renders the 'sent to' line when an email is provided" do
    result = render_inline(described_class.new(email: "alice@example.com"))

    expect(result.text).to include(
      I18n.t("opensop.auth.magic_link_sent.sent_to", email: "alice@example.com")
    )
  end

  it "omits the 'sent to' line when no email is provided" do
    result = render_inline(described_class.new)

    expect(result.text).not_to include("Sent to")
  end

  describe "dev banner" do
    let(:dev_url) { "http://localhost:3000/auth/magic_links/abc123tokenvalue" }

    it "renders the amber banner when dev_url: is present" do
      result = render_inline(described_class.new(dev_url: dev_url))

      banner = result.at_css(".bg-amber-50.border-amber-300")
      expect(banner).not_to be_nil
    end

    it "renders the URL text inside the banner so users can copy it" do
      result = render_inline(described_class.new(dev_url: dev_url))

      expect(result.text).to include(dev_url)
    end

    it "renders an <a> with href equal to the dev_url" do
      result = render_inline(described_class.new(dev_url: dev_url))

      anchor = result.at_css("a[href='#{dev_url}']")
      expect(anchor).not_to be_nil
      expect(anchor.text).to include(I18n.t("opensop.auth.magic_link_sent.dev.cta"))
    end

    it "renders the 'DEV MODE' tag and the translated label" do
      result = render_inline(described_class.new(dev_url: dev_url))

      # The component template hard-codes the visual "dev mode" pill text and
      # then renders the i18n label next to it.
      expect(result.text.downcase).to include("dev mode")
      expect(result.text).to include(I18n.t("opensop.auth.magic_link_sent.dev.label"))
    end

    it "does NOT render the banner when dev_url: is nil" do
      result = render_inline(described_class.new(dev_url: nil))

      expect(result.at_css(".bg-amber-50.border-amber-300")).to be_nil
      expect(result.text.downcase).not_to include("dev mode")
    end

    it "does NOT render the banner when dev_url: is an empty string" do
      result = render_inline(described_class.new(dev_url: ""))

      expect(result.at_css(".bg-amber-50.border-amber-300")).to be_nil
      expect(result.text.downcase).not_to include("dev mode")
    end
  end
end
