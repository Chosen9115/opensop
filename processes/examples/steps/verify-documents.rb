#!/usr/bin/env ruby
# frozen_string_literal: true

# Automated step: verify-documents
#
# Reads an inputs JSON from stdin:
#   { "business_record": { ... }, "documents": [ ... ] }
#
# Emits an outputs JSON to stdout matching the step's output schema:
#   { "verification_result": "complete"|"incomplete"|"invalid",
#     "missing_documents": [ string, ... ] }

require "json"

raw = $stdin.read
payload =
  begin
    raw.to_s.strip.empty? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end

business_record = payload["business_record"]
documents = payload["documents"]

result =
  if business_record.nil? || (business_record.respond_to?(:empty?) && business_record.empty?)
    { "verification_result" => "invalid", "missing_documents" => [ "business_record" ] }
  else
    missing = []
    if documents.is_a?(Array) && documents.empty?
      # Documents key was present but empty — treat as incomplete rather than invalid.
      { "verification_result" => "incomplete", "missing_documents" => [ "supporting_documents" ] }
    else
      { "verification_result" => "complete", "missing_documents" => missing }
    end
  end

puts JSON.generate(result)
