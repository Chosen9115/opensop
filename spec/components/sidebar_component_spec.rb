# frozen_string_literal: true

require "rails_helper"
require "view_component/test_helpers"

RSpec.describe SidebarComponent, type: :component do
  include ViewComponent::TestHelpers

  # ApplicationController inherits from ActionController::API which lacks a
  # view_context. Override to a Base controller subclass that explicitly
  # includes the application's route helpers so `helpers.ui_*_path` resolves
  # inside the component's instance methods (route helpers aren't auto-mixed
  # into a stock ActionController::Base in the test harness).
  TestController = Class.new(ActionController::Base) do
    include Rails.application.routes.url_helpers
  end

  def vc_test_controller_class
    TestController
  end

  let(:current_path) { "/ui/dashboard" }
  let(:counts)       { { processes: 0, instances_running: 0 } }
  let(:user)         { build_stubbed(:user, email: "admin@example.com") }

  def render_with(user: nil, path: current_path)
    render_inline(described_class.new(current_path: path, counts: counts, current_user: user))
  end

  describe "Account section" do
    it "is hidden when no user is signed in" do
      result = render_with(user: nil)
      expect(result.text).not_to include("Account")
    end

    context "when a user is signed in" do
      it "shows the Account section heading" do
        result = render_with(user: user)
        expect(result.text).to include("Account")
      end

      it "renders a Passkeys link pointing to ui_account_passkeys_path" do
        result = render_with(user: user)
        link = result.at_css('a[href="/account/passkeys"]')
        expect(link).not_to be_nil
        expect(link.text).to include("Passkeys")
      end

      it "renders a Users link pointing to ui_account_users_path" do
        result = render_with(user: user)
        link = result.at_css('a[href="/account/users"]')
        expect(link).not_to be_nil
        expect(link.text).to include("Users")
      end

      it "highlights the Users link as active when on /ui/account/users" do
        result = render_with(user: user, path: "/account/users")
        link = result.at_css('a[href="/account/users"]')
        expect(link["class"]).to include("bg-bg-hover")
        expect(link["class"]).to include("font-medium")
      end

      it "does not highlight Users when viewing a different page" do
        result = render_with(user: user, path: "/ui/dashboard")
        link = result.at_css('a[href="/account/users"]')
        expect(link["class"]).not_to include("font-medium")
      end
    end
  end

  describe "account section structure" do
    it "renders Passkeys before Users in the Account section" do
      result = render_with(user: user)
      account_links = result.css('a[href^="/account/"]').map { |a| a.text.strip }
      passkeys_idx = account_links.index { |t| t.include?("Passkeys") }
      users_idx    = account_links.index { |t| t.include?("Users") }
      expect(passkeys_idx).not_to be_nil
      expect(users_idx).not_to be_nil
      expect(passkeys_idx).to be < users_idx
    end

    it "uses a different icon path than Agents (so the two don't visually collide)" do
      result = render_with(user: user)
      agents_link = result.at_css('a[href="/agents"]')
      users_link  = result.at_css('a[href="/account/users"]')
      expect(agents_link).not_to be_nil
      expect(users_link).not_to be_nil
      agents_icon = agents_link.at_css("svg path")["d"]
      users_icon  = users_link.at_css("svg path")["d"]
      expect(users_icon).not_to eq(agents_icon)
    end
  end
end
