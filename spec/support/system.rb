# frozen_string_literal: true

# System specs drive a real headless Chrome via Selenium.
# Requires Google Chrome (or Chromium) installed locally.
# Selenium 4+ ships its own driver manager — no chromedriver gem needed.

require "capybara/rails"
require "capybara/rspec"
require "selenium-webdriver"

Capybara.register_driver :headless_chrome do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--disable-gpu")
  options.add_argument("--no-sandbox")
  options.add_argument("--window-size=1280,900")
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :headless_chrome
  end
end
