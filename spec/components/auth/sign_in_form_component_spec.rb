# frozen_string_literal: true

require "rails_helper"
require "view_component/test_helpers"

RSpec.describe Auth::SignInFormComponent, type: :component do
  include ViewComponent::TestHelpers

  # Same trick as the existing KeyValueListComponent spec — the app's
  # ApplicationController inherits from ActionController::API which lacks a
  # view_context. Override to a plain Base controller so url_for and form
  # helpers work in the rendering harness.
  def vc_test_controller_class
    ActionController::Base
  end

  it "renders without errors" do
    expect { render_inline(described_class.new) }.not_to raise_error
  end

  it "renders the i18n heading" do
    result = render_inline(described_class.new)

    expect(result.text).to include(I18n.t("opensop.auth.sign_in.heading"))
  end

  describe "email field" do
    it "carries autocomplete='username webauthn' to enable conditional UI" do
      result = render_inline(described_class.new)

      input = result.at_css('input[type="email"]')
      expect(input).not_to be_nil
      expect(input["autocomplete"]).to eq("username webauthn")
    end

    it "is wired to the passkey-signin Stimulus target" do
      result = render_inline(described_class.new)

      input = result.at_css('input[type="email"][data-passkey-signin-target="email"]')
      expect(input).not_to be_nil
    end
  end

  describe "submit paths" do
    it "renders the passkey button with the Stimulus action" do
      result = render_inline(described_class.new)

      button = result.at_css('button[data-action="passkey-signin#submit"]')
      expect(button).not_to be_nil
      expect(button["data-passkey-signin-target"]).to eq("submit")
      expect(button.text).to include(I18n.t("opensop.auth.sign_in.passkey_cta"))
    end

    it "renders the magic-link submit button" do
      result = render_inline(described_class.new)

      buttons = result.css('button[type="submit"]').map(&:text).map(&:strip)
      expect(buttons.any? { |t| t.include?(I18n.t("opensop.auth.sign_in.magic_link_cta")) }).to be true
    end
  end

  describe "form attributes" do
    it "wires the form to the passkey-signin controller with options + verify URLs" do
      result = render_inline(described_class.new)

      form = result.at_css("form")
      expect(form["data-controller"]).to include("passkey-signin")
      expect(form["data-passkey-signin-options-url-value"]).to eq("/auth/passkey/options")
      expect(form["data-passkey-signin-verify-url-value"]).to eq("/auth/passkey/verify")
    end

    it "passes return_to through as a hidden field when provided" do
      result = render_inline(described_class.new(return_to: "/instances"))

      hidden = result.at_css('input[type="hidden"][name="return_to"]')
      expect(hidden).not_to be_nil
      expect(hidden["value"]).to eq("/instances")
    end
  end

  describe "recovery block" do
    it "renders a <details> element with the recovery copy" do
      result = render_inline(described_class.new)

      details = result.at_css("details")
      expect(details).not_to be_nil
      expect(details.text).to include(I18n.t("opensop.auth.sign_in.recovery_link"))
      expect(details.text).to include(I18n.t("opensop.auth.sign_in.recovery_cta"))
    end
  end

  describe "Turbo opt-out (regression)" do
    # Regression: Rails 8 `form_with local: true` does not consistently render
    # `data-turbo="false"`. Without this attribute, Turbo intercepts the POST
    # to /auth/magic_links, swallows the HTML response, and the
    # "check your email" confirmation page (including the dev magic-link
    # banner) never displays. The component template now sets
    # `data: { turbo: false }` explicitly on both forms — this spec locks
    # that behavior in.

    it "renders data-turbo='false' on the main passkey/magic-link form" do
      result = render_inline(described_class.new)

      main_form = result.css('form[action*="/auth/magic_links"]').first
      expect(main_form).not_to be_nil
      expect(main_form["data-turbo"]).to eq("false")
    end

    it "renders data-turbo='false' on the recovery sub-form inside <details>" do
      result = render_inline(described_class.new)

      details = result.at_css("details")
      expect(details).not_to be_nil

      recovery_form = details.at_css('form[action*="/auth/magic_links"]')
      expect(recovery_form).not_to be_nil
      expect(recovery_form["data-turbo"]).to eq("false")
    end

    it "renders data-turbo='false' on every magic-link form in the component" do
      result = render_inline(described_class.new)

      forms = result.css('form[action*="/auth/magic_links"]')
      expect(forms.length).to be >= 2
      forms.each do |form|
        expect(form["data-turbo"]).to eq("false"),
          "expected form with action #{form['action'].inspect} to have data-turbo='false'"
      end
    end
  end

  describe "error and fallback regions" do
    it "renders the hidden error region as a Stimulus target" do
      result = render_inline(described_class.new)

      error = result.at_css('[data-passkey-signin-target="error"]')
      expect(error).not_to be_nil
      expect(error["class"]).to include("hidden")
    end

    it "renders the hidden no-WebAuthn fallback region with translated copy" do
      result = render_inline(described_class.new)

      fallback = result.at_css("[data-passkey-fallback]")
      expect(fallback).not_to be_nil
      expect(fallback["class"]).to include("hidden")
      expect(fallback.text).to include(I18n.t("opensop.auth.sign_in.fallback_no_webauthn"))
    end
  end
end
