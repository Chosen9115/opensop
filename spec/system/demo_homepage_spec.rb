# frozen_string_literal: true

require "rails_helper"

# Smoke-walk through the demo homepage. Drives real headless Chrome via
# Selenium. The spec seeds at least one sample process so the process card
# grid is populated, visits /, checks the banner and token, then clicks
# through to the process show page.

RSpec.describe "Demo homepage smoke walk", type: :system do
  around do |example|
    original = ENV["DEMO_MODE"]
    ENV["DEMO_MODE"] = "true"
    example.run
  ensure
    original.nil? ? ENV.delete("DEMO_MODE") : ENV["DEMO_MODE"] = original
  end

  before do
    # Disable UI basic-auth so headless Chrome can reach the page.
    ENV.delete("OPENSOP_UI_USER")
    ENV.delete("OPENSOP_UI_PASSWORD")
    # Seed at least one process so the grid renders a card.
    Demo::SeedLoader.call
  end

  it "shows the API token, the demo banner, and at least one process card, then navigates to the process show page" do
    visit "/"

    # Banner
    expect(page).to have_text(Opensop::DemoMode::RESET_SCHEDULE_HUMAN)

    # API token is displayed
    expect(page).to have_text(Opensop::DemoMode.api_token)

    # At least one process card is visible
    first_process = Sop::Process.published.order(:name).first
    expect(first_process).not_to be_nil, "expected at least one seeded process"
    expect(page).to have_text(first_process.name, normalize_ws: true)

    # Click into the first process card — the show page should render without errors
    first_link = find("a", text: /#{Regexp.escape(first_process.name)}/i, match: :first)
    first_link.click

    # Selenium doesn't expose status_code — assert on content instead.
    expect(page).to have_text(first_process.name, normalize_ws: true)
    expect(page).not_to have_text("Internal Server Error")
  end
end
