source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"

# Use Active Model has_secure_password
gem "bcrypt", "~> 3.1.7"

# JSON serialization
gem "oj"

# HTTP client for webhook calls
gem "httparty"

# YAML parsing (process definitions)
gem "psych"

# CORS for API access
gem "rack-cors"

# Hotwire for UI
gem "turbo-rails"
gem "stimulus-rails"
gem "importmap-rails"

# Asset pipeline
gem "propshaft"
gem "tailwindcss-rails"

# ViewComponent for UI components
gem "view_component"

# Pagination
gem "pagy"

# Heroicons
gem "heroicon"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache and Active Job
gem "solid_cache"
gem "solid_queue"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Rack CORS for handling Cross-Origin Resource Sharing (CORS), making cross-origin Ajax possible
# gem "rack-cors"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false

  # Testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "shoulda-matchers"
  gem "webmock"
  gem "faker"
end

group :test do
  gem "database_cleaner-active_record"
  gem "simplecov", require: false

  # System specs run against headless Chrome via Selenium.
  gem "capybara"
  gem "selenium-webdriver"
end

gem "webauthn", "~> 3.4"
gem "resend", "~> 1.3"
gem "rack-attack", "~> 6.8"
