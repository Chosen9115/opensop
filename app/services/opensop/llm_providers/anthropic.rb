# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "yaml"

module Opensop
  module LlmProviders
    # Anthropic Claude provider implemented directly against the Messages API
    # (https://api.anthropic.com/v1/messages). No gem dependency — pure Net::HTTP
    # so wave coordination doesn't need a Gemfile change.
    #
    # Output contract: the model is instructed to return ONLY a JSON object
    # matching the supplied schema. The response text is parsed as JSON; code
    # fences (```json ... ```) are stripped if present.
    class Anthropic < Base
      API_URL = "https://api.anthropic.com/v1/messages"
      API_VERSION = "2023-06-01"
      DEFAULT_MODEL = "claude-sonnet-4-7"
      DEFAULT_MAX_TOKENS = 4096
      OPEN_TIMEOUT_SECONDS = 10
      READ_TIMEOUT_SECONDS = 120

      def initialize(api_key: ENV["ANTHROPIC_API_KEY"], model: DEFAULT_MODEL)
        super()
        @api_key = api_key
        @model = model
      end

      def call(prompt:, tools: [], expected_output_schema: nil, temperature: nil, max_tokens: nil)
        raise CallFailed, "ANTHROPIC_API_KEY is not set" if @api_key.nil? || @api_key.to_s.empty?

        body = build_request_body(
          prompt: prompt,
          expected_output_schema: expected_output_schema,
          temperature: temperature,
          max_tokens: max_tokens
        )

        http_response = post_json(body)

        unless http_response.is_a?(Net::HTTPSuccess)
          raise CallFailed,
                "Anthropic API returned HTTP #{http_response.code}: #{truncate(http_response.body)}"
        end

        payload =
          begin
            JSON.parse(http_response.body)
          rescue JSON::ParserError => e
            raise CallFailed, "Anthropic API returned non-JSON response: #{e.message}"
          end

        raw_text = extract_text(payload)
        content_hash = parse_content_json(raw_text)

        usage = payload["usage"] || {}

        Response.new(
          content: content_hash,
          raw_text: raw_text,
          input_tokens: (usage["input_tokens"] || 0).to_i,
          output_tokens: (usage["output_tokens"] || 0).to_i,
          cost_cents: nil,
          model: payload["model"] || @model,
          tool_calls: []
        )
      end

      private

      def build_request_body(prompt:, expected_output_schema:, temperature:, max_tokens:)
        schema_yaml =
          if expected_output_schema.is_a?(Hash) && !expected_output_schema.empty?
            expected_output_schema.to_yaml
          else
            "{} # any JSON object"
          end

        system_prompt = <<~SYS.strip
          You are a precise JSON generator. Respond ONLY with a JSON object matching this schema:
          #{schema_yaml}
          No prose, no code fences.
        SYS

        body = {
          model: @model,
          max_tokens: max_tokens || DEFAULT_MAX_TOKENS,
          system: system_prompt,
          messages: [
            { role: "user", content: prompt.to_s }
          ]
        }
        body[:temperature] = temperature unless temperature.nil?
        body
      end

      def post_json(body)
        uri = URI.parse(API_URL)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = OPEN_TIMEOUT_SECONDS
        http.read_timeout = READ_TIMEOUT_SECONDS

        request = Net::HTTP::Post.new(uri.request_uri)
        request["x-api-key"] = @api_key
        request["anthropic-version"] = API_VERSION
        request["content-type"] = "application/json"
        request.body = JSON.dump(body)

        http.request(request)
      rescue StandardError => e
        raise CallFailed, "Anthropic API request failed: #{e.class}: #{e.message}"
      end

      def extract_text(payload)
        blocks = payload["content"]
        unless blocks.is_a?(Array) && blocks.any?
          raise CallFailed, "Anthropic API response missing content blocks"
        end

        first_text_block = blocks.find { |b| b.is_a?(Hash) && b["type"] == "text" } || blocks.first
        text = first_text_block.is_a?(Hash) ? first_text_block["text"] : nil
        unless text.is_a?(String) && !text.empty?
          raise CallFailed, "Anthropic API response has no text content"
        end

        text
      end

      def parse_content_json(raw_text)
        cleaned = strip_code_fence(raw_text).strip
        parsed =
          begin
            JSON.parse(cleaned)
          rescue JSON::ParserError => e
            raise CallFailed, "Model output is not valid JSON: #{e.message} — got: #{truncate(raw_text)}"
          end

        unless parsed.is_a?(Hash)
          raise CallFailed, "Model output must be a JSON object, got #{parsed.class}"
        end

        parsed
      end

      # Strips a ```json ... ``` or ``` ... ``` fence if present.
      def strip_code_fence(text)
        match = text.strip.match(/\A```(?:json)?\s*\n?(.*?)\n?```\z/m)
        match ? match[1] : text
      end

      def truncate(str, limit: 500)
        return "" if str.nil?
        s = str.to_s
        s.length > limit ? s[0, limit] + "…" : s
      end
    end
  end
end
