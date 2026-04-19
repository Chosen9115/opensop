#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: send-welcome
#
# (In the customer-onboarding process this step is actually declared as a
# `notification` step type, so the notification stub handles it. This
# script is provided for parity and to support automated-style usage.)
#
# Reads an inputs JSON from stdin:
#   { "contact_email": "...", "account_id": "..." }
#
# Emits an outputs JSON:
#   { "email_sent": true }

require "json"

raw = $stdin.read
begin
  raw.to_s.strip.empty? ? {} : JSON.parse(raw)
rescue JSON::ParserError
  {}
end

puts JSON.generate("email_sent" => true)
