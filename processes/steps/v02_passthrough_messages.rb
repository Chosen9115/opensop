#!/usr/bin/env ruby
# frozen_string_literal: true

# Smoke step: v02_passthrough_messages
#
# Reads { "messages": [...] } from stdin and echoes the same array back so the
# downstream loop step has a collection-shaped output to fan over.

require "json"

raw = $stdin.read
input =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

puts JSON.dump("messages" => input["messages"])
