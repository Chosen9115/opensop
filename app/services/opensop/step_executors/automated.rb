# frozen_string_literal: true

require "open3"
require "json"

module Opensop
  module StepExecutors
    # Executes `automated` steps by running the configured script.
    # Protocol (SPEC §6.3):
    #   engine  --stdin (JSON of inputs)-->  script
    #   script  --stdout (JSON of outputs)-->  engine
    #
    # Missing script => StepFailure so the instance fails loudly.
    class Automated
      class StepFailure < StandardError; end

      DEFAULT_TIMEOUT_SECONDS = 60

      def call(step, instance, definition)
        run_path = definition["run"]
        raise StepFailure, "automated step is missing `run:` path" if run_path.blank?

        resolved = resolve_script_path(run_path)
        unless File.exist?(resolved)
          raise StepFailure, "script not found at #{resolved} (run: #{run_path.inspect})"
        end
        unless File.executable?(resolved) || interpretable?(resolved)
          raise StepFailure, "script at #{resolved} is not executable"
        end

        command = build_command(resolved)
        timeout_seconds = (definition["timeout_seconds"] || DEFAULT_TIMEOUT_SECONDS).to_i
        payload = JSON.dump(step.inputs || {})

        Rails.logger.info("[Opensop::StepExecutors::Automated] running #{command.join(" ")} for step=#{step.step_id}")

        stdout, stderr, status = nil
        begin
          Timeout.timeout(timeout_seconds) do
            stdout, stderr, status = Open3.capture3(*command, stdin_data: payload)
          end
        rescue Timeout::Error
          raise StepFailure, "script timed out after #{timeout_seconds}s"
        end

        unless status.success?
          raise StepFailure,
                "script exited with status #{status.exitstatus}: #{truncate(stderr || stdout)}"
        end

        parsed =
          begin
            JSON.parse(stdout.to_s.strip.empty? ? "{}" : stdout)
          rescue JSON::ParserError => e
            raise StepFailure, "script stdout is not valid JSON: #{e.message} — got: #{truncate(stdout)}"
          end

        unless parsed.is_a?(Hash)
          raise StepFailure, "script stdout must be a JSON object, got #{parsed.class}"
        end

        validation_mode = definition["validation"] || "lenient"
        if validation_mode == "strict"
          declared_names = Array(definition["outputs"]).map { |o| o["name"].to_s }
          missing = declared_names.reject { |n| parsed.key?(n) }
          if missing.any?
            raise StepFailure,
                  "validation: strict — script stdout is missing declared output(s): #{missing.join(", ")}. " \
                  "Got keys: #{parsed.keys.inspect}."
          end
        end

        { outputs: parsed }
      end

      private

      def resolve_script_path(run_path)
        pn = Pathname.new(run_path)
        return pn.to_s if pn.absolute?
        Rails.root.join("processes", run_path).to_s
      end

      def interpretable?(path)
        first = File.open(path, "r") { |f| f.readline }
        first&.start_with?("#!")
      rescue StandardError
        false
      end

      def build_command(path)
        ext = File.extname(path).downcase
        case ext
        when ".rb"  then ["ruby", path]
        when ".py"  then ["python3", path]
        when ".js"  then ["node", path]
        when ".sh"  then ["bash", path]
        else [path]
        end
      end

      def truncate(str, limit: 500)
        return "" if str.nil?
        str.length > limit ? str[0, limit] + "…" : str
      end
    end
  end
end
