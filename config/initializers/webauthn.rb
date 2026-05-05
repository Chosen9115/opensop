# frozen_string_literal: true

# WebAuthn relying-party configuration. Required env in production:
#   OPENSOP_RP_ID  — relying-party ID (apex domain, e.g. "opensop.example.com")
#   OPENSOP_ORIGIN — full origin URL for assertion validation (e.g. "https://opensop.example.com")
# Optional:
#   OPENSOP_RP_NAME — display name (default "OpenSOP")
#
# In dev/test we fall back to localhost defaults so contributors don't need
# to configure WebAuthn just to boot Rails.
require "webauthn"

WebAuthn.configure do |config|
  origin = ENV["OPENSOP_ORIGIN"].presence ||
           (Rails.env.production? ? nil : "http://localhost:3000")
  config.allowed_origins = [origin].compact
  config.rp_id = ENV["OPENSOP_RP_ID"].presence ||
                  (Rails.env.production? ? nil : "localhost")
  config.rp_name = ENV["OPENSOP_RP_NAME"].presence || "OpenSOP"
  config.credential_options_timeout = 60_000
  config.encoding = :base64url
end

# Production fail-closed parity with admin_ui_auth.rb.
if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].to_s.strip.empty?
  if ENV["OPENSOP_RP_ID"].to_s.strip.empty? || ENV["OPENSOP_ORIGIN"].to_s.strip.empty?
    raise(
      "[SECURITY] OPENSOP_RP_ID and OPENSOP_ORIGIN must both be set in production. " \
      "WebAuthn ceremonies require a relying-party ID and origin to validate."
    )
  end
end
