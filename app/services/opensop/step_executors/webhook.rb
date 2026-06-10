# frozen_string_literal: true

require "httparty"

module Opensop
  module StepExecutors
    # Webhook step — fires an outbound HTTP call and either returns its
    # response as the step outputs (sync mode) or pauses the instance
    # until a third party posts to the generated callback URL (callback
    # mode).
    #
    # YAML shape:
    #
    #   - id: submit-to-compliance
    #     type: webhook
    #     webhook:
    #       method: POST                          # GET | POST | PUT | PATCH | DELETE
    #       url: "${env.PROVIDER_URL}/entities"   # ${env.X}, ${inputs.Y}, ${callback_url}
    #       headers:
    #         Authorization: "Bearer ${env.PROVIDER_API_KEY}"
    #         Content-Type: "application/json"
    #       body_template: ./steps/payload.json   # optional; else inputs used
    #       response_mode: callback                    # sync | callback | poll
    #       poll_timeout: 7d                           # callback mode only
    #
    # The inbound callback path is auto-generated as /sop/webhooks/<uuid>
    # and injected as ${callback_url} wherever the template references it.
    class Webhook
      class StepFailure < StandardError; end

      ALLOWED_METHODS = %w[GET POST PUT PATCH DELETE].freeze
      ALLOWED_MODES = %w[sync callback poll].freeze
      DEFAULT_TIMEOUT_SECONDS = 30

      def call(step, instance, definition)
        config = definition["webhook"] || {}
        mode = (config["response_mode"] || "callback").to_s.downcase

        unless ALLOWED_MODES.include?(mode)
          raise StepFailure, "unknown response_mode: #{mode.inspect} (must be one of #{ALLOWED_MODES.inspect})"
        end

        case mode
        when "sync"     then execute_sync(step, instance, config)
        when "callback" then execute_callback(step, instance, config)
        when "poll"     then raise StepFailure, "response_mode: poll is not implemented yet (see SPEC §8 roadmap)"
        end
      end

      private

      def execute_sync(step, instance, config)
        response = fire_request(step, instance, config, callback_url: nil)
        raise_unless_success!(response, mode: "sync")

        outputs = parse_response(response)
        emit_event(instance, step, config, response: response.code, mode: "sync")
        { outputs: outputs }
      end

      def execute_callback(step, instance, config)
        callback = instance.callbacks.create!(
          step_id: step.step_id,
          status: "pending",
          response: {},
          expires_at: parse_timeout(config["poll_timeout"])
        )

        begin
          response = fire_request(step, instance, config, callback_url: full_callback_url(callback))
          raise_unless_success!(response, mode: "callback")
        rescue StandardError
          callback.destroy
          raise
        end

        emit_event(instance, step, config, response: response.code, mode: "callback",
                                           callback_path: callback.callback_path)
        { waiting: "waiting_for_callback" }
      end

      def fire_request(step, instance, config, callback_url:)
        url = render(config["url"], step, instance, callback_url)
        raise StepFailure, "webhook.url is required" if url.blank?

        method = (config["method"] || "POST").to_s.upcase
        raise StepFailure, "unsupported HTTP method: #{method.inspect}" unless ALLOWED_METHODS.include?(method)

        headers = (config["headers"] || {}).transform_values { |v| render(v, step, instance, callback_url) }
        body    = build_body(config, step, instance, callback_url)

        http_call(method, url, headers, body)
      rescue Opensop::Templating::MissingVariable => e
        raise StepFailure, "template error: #{e.message}"
      rescue HTTParty::Error, SocketError, Errno::ECONNREFUSED, Timeout::Error, Net::OpenTimeout, Net::ReadTimeout => e
        raise StepFailure, "outbound request failed (#{e.class}): #{e.message}"
      end

      def http_call(method, url, headers, body)
        opts = { headers: headers, timeout: DEFAULT_TIMEOUT_SECONDS }
        opts[:body] = body unless %w[GET DELETE].include?(method) || body.nil?

        HTTParty.send(method.downcase, url, **opts)
      end

      def build_body(config, step, instance, callback_url)
        template_path = config["body_template"]

        if template_path.present?
          raw = load_template(template_path)
          render(raw, step, instance, callback_url)
        else
          # No template: send resolved step inputs as JSON. Types preserved.
          JSON.dump(step.inputs || {})
        end
      end

      def load_template(path)
        resolved = if Pathname.new(path).absolute?
          path
        else
          Rails.root.join("processes", path).to_s
        end
        raise StepFailure, "body_template not found at #{resolved}" unless File.exist?(resolved)
        File.read(resolved)
      end

      def render(string, step, instance, callback_url)
        Opensop::Templating.render(
          string,
          step_inputs:    step.inputs || {},
          process_inputs: instance.inputs || {},
          callback_url:   callback_url
        )
      end

      def raise_unless_success!(response, mode:)
        code = response.code.to_i
        return if code.between?(200, 299)
        raise StepFailure, "#{mode} webhook HTTP #{code}: #{truncate(response.body.to_s)}"
      end

      def parse_response(response)
        body = response.body.to_s
        return {} if body.strip.empty?
        parsed = JSON.parse(body)
        raise StepFailure, "sync webhook response must be a JSON object, got #{parsed.class}" unless parsed.is_a?(Hash)
        parsed
      rescue JSON::ParserError => e
        raise StepFailure, "sync webhook response is not valid JSON: #{e.message} — got: #{truncate(body)}"
      end

      def full_callback_url(callback)
        base = ENV["OPENSOP_BASE_URL"].presence || "http://localhost:3000"
        "#{base.chomp("/")}#{callback.callback_path}"
      end

      def emit_event(instance, step, config, **extra)
        instance.events.create!(
          step_id: step.step_id,
          event_type: "step.webhook_dispatched",
          actor: "system",
          data: {
            method: config["method"],
            url:    config["url"]
          }.merge(extra.transform_keys(&:to_s))
        )
      end

      def parse_timeout(value)
        return nil if value.blank?
        seconds = duration_to_seconds(value.to_s)
        seconds ? seconds.seconds.from_now : nil
      end

      def duration_to_seconds(str)
        if (m = str.match(/\A(\d+)\s*([smhdwMy])\z/))
          unit = { "s" => 1, "m" => 60, "h" => 3600, "d" => 86_400,
                   "w" => 604_800, "M" => 2_592_000, "y" => 31_536_000 }[m[2]]
          m[1].to_i * unit
        end
      end

      def truncate(str, limit: 300)
        str = str.to_s
        str.length > limit ? "#{str[0, limit]}…" : str
      end
    end
  end
end
