require 'rails_helper'

RSpec.describe Opensop::DefinitionParser do
  def minimal_process(overrides = {})
    {
      "opensop" => "0.1",
      "process" => {
        "name" => "test-proc",
        "version" => "1.0",
        "steps" => []
      }.merge(overrides)
    }
  end

  describe ".call" do
    it "accepts a valid hash" do
      result = described_class.call(minimal_process)
      expect(result.ok?).to be true
      expect(result.value["process"]["name"]).to eq("test-proc")
    end

    it "accepts a valid YAML string" do
      yaml = YAML.dump(minimal_process)
      result = described_class.call(yaml)
      expect(result.ok?).to be true
    end

    it "stringifies symbol keys in an input hash" do
      result = described_class.call(
        opensop: "0.1",
        process: { name: "sym-proc", version: "1.0", steps: [] }
      )
      expect(result.value.keys).to include("opensop", "process")
    end

    it "accepts the real customer-onboarding.sop.yaml" do
      path = Rails.root.join("processes/examples/customer-onboarding.sop.yaml")
      raw = File.read(path)
      result = described_class.call(raw)

      expect(result.ok?).to be true
      expect(result.value.dig("process", "name")).to eq("customer-onboarding")
    end

    describe "top-level validation" do
      it "rejects a missing opensop key" do
        expect { described_class.call("process" => { "name" => "x", "version" => "1.0", "steps" => [] }) }
          .to raise_error(described_class::InvalidDefinition, /opensop.*missing/)
      end

      it "rejects a wrong opensop version" do
        hash = minimal_process
        hash["opensop"] = "9.9"
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /unsupported version/)
      end

      it "rejects a missing process block" do
        expect { described_class.call("opensop" => "0.1") }
          .to raise_error(described_class::InvalidDefinition, /missing process block/)
      end

      it "rejects non-hash/non-string input" do
        expect { described_class.call(123) }.to raise_error(described_class::InvalidDefinition)
      end
    end

    describe "process-level validation" do
      it "rejects a missing name" do
        hash = minimal_process
        hash["process"].delete("name")
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /process\.name/)
      end

      it "rejects an empty name" do
        expect { described_class.call(minimal_process("name" => "")) }
          .to raise_error(described_class::InvalidDefinition, /process\.name/)
      end
    end

    describe "step validation" do
      it "rejects an invalid step id format" do
        hash = minimal_process("steps" => [ { "id" => "BAD ID", "name" => "x", "type" => "notification" } ])
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /invalid format/)
      end

      it "rejects duplicate step ids within a process" do
        hash = minimal_process("steps" => [
          { "id" => "one", "name" => "One",  "type" => "notification" },
          { "id" => "one", "name" => "One2", "type" => "notification" }
        ])
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /duplicate step id/)
      end

      it "rejects an unknown step type" do
        hash = minimal_process("steps" => [ { "id" => "x", "name" => "X", "type" => "bogus" } ])
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /unknown step type/)
      end

      it "rejects an automated step without `run:`" do
        hash = minimal_process("steps" => [ { "id" => "a", "name" => "A", "type" => "automated" } ])
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /requires a `run` path/)
      end

      it "rejects a webhook step missing the webhook block" do
        hash = minimal_process("steps" => [ { "id" => "w", "name" => "W", "type" => "webhook" } ])
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /webhook/)
      end

      it "rejects a webhook step missing url / method / response_mode" do
        hash = minimal_process("steps" => [ {
          "id" => "w", "name" => "W", "type" => "webhook",
          "webhook" => { "method" => "POST" }
        } ])
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /webhook\.url/)
      end

      it "rejects a subprocess step missing `process:`" do
        hash = minimal_process("steps" => [ { "id" => "s", "name" => "S", "type" => "subprocess" } ])
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /subprocess/)
      end
    end

    describe "trigger validation" do
      def with_trigger(trigger)
        minimal_process("trigger" => trigger)
      end

      def valid_webhook_trigger(overrides = {})
        {
          "type" => "webhook",
          "auth" => {
            "scheme"     => "hmac-sha256",
            "secret_env" => "WEBHOOK_SECRET",
            "header"     => "X-Signature"
          },
          "input_mapping" => { "email" => "${payload.email}" }
        }.deep_merge(overrides)
      end

      it "accepts a valid webhook trigger" do
        result = described_class.call(with_trigger(valid_webhook_trigger))
        expect(result.ok?).to be true
      end

      it "accepts trigger: type: api with no auth block" do
        result = described_class.call(with_trigger({ "type" => "api" }))
        expect(result.ok?).to be true
      end

      it "rejects an unknown trigger type" do
        expect { described_class.call(with_trigger({ "type" => "carrier-pigeon" })) }
          .to raise_error(described_class::InvalidDefinition, /unknown trigger type/)
      end

      it "rejects a webhook trigger without an auth block" do
        trigger = valid_webhook_trigger
        trigger.delete("auth")
        expect { described_class.call(with_trigger(trigger)) }
          .to raise_error(described_class::InvalidDefinition, /requires an `auth` block/)
      end

      it "rejects an unsupported auth scheme" do
        expect { described_class.call(with_trigger(valid_webhook_trigger("auth" => { "scheme" => "rsa-pss" }))) }
          .to raise_error(described_class::InvalidDefinition, /unsupported scheme/)
      end

      it "rejects a missing secret_env" do
        t = valid_webhook_trigger
        t["auth"].delete("secret_env")
        expect { described_class.call(with_trigger(t)) }
          .to raise_error(described_class::InvalidDefinition, /secret_env/)
      end

      it "rejects an unsupported encoding" do
        expect { described_class.call(with_trigger(valid_webhook_trigger("auth" => { "encoding" => "rot13" }))) }
          .to raise_error(described_class::InvalidDefinition, /unsupported encoding/)
      end

      it "rejects a non-string prefix" do
        expect { described_class.call(with_trigger(valid_webhook_trigger("auth" => { "prefix" => 42 }))) }
          .to raise_error(described_class::InvalidDefinition, /prefix/)
      end

      it "rejects an input_mapping value of the wrong type" do
        expect { described_class.call(with_trigger(valid_webhook_trigger("input_mapping" => { "x" => [] }))) }
          .to raise_error(described_class::InvalidDefinition, /input_mapping/)
      end
    end

    describe "v0.2 features" do
      def v02_process(steps:, extra_process: {})
        {
          "opensop" => "0.2",
          "process" => {
            "name" => "v02-proc",
            "version" => "1.0",
            "steps" => steps
          }.merge(extra_process)
        }
      end

      def valid_llm_step(overrides = {})
        {
          "id" => "classify",
          "name" => "Classify",
          "type" => "llm",
          "model" => "claude-sonnet-4-7",
          "prompt" => "Classify the message: {{ message }}",
          "expected_output_schema" => {
            "intent" => "enum[question, task, complaint]",
            "confidence" => "number"
          }
        }.merge(overrides)
      end

      it "still accepts v0.1 files (no regression)" do
        result = described_class.call(minimal_process)
        expect(result.ok?).to be true
        expect(result.value["opensop"]).to eq("0.1")
      end

      it "accepts opensop: '0.2'" do
        result = described_class.call(v02_process(steps: []))
        expect(result.ok?).to be true
        expect(result.value["opensop"]).to eq("0.2")
      end

      it "accepts a valid llm step and applies defaults" do
        result = described_class.call(v02_process(steps: [valid_llm_step]))
        expect(result.ok?).to be true
        step = result.value["process"]["steps"].first
        expect(step["tools"]).to eq([])
        expect(step["retry_on_incomplete"]).to be true
        expect(step["max_retries"]).to eq(2)
      end

      it "accepts an llm step using prompt_file instead of prompt" do
        step = valid_llm_step
        step.delete("prompt")
        step["prompt_file"] = "prompts/classify.md"
        result = described_class.call(v02_process(steps: [step]))
        expect(result.ok?).to be true
      end

      it "rejects an llm step with both prompt and prompt_file" do
        step = valid_llm_step("prompt_file" => "prompts/classify.md")
        expect { described_class.call(v02_process(steps: [step])) }
          .to raise_error(
            described_class::InvalidDefinition,
            /llm step 'classify' requires either prompt: or prompt_file:, not both/
          )
      end

      it "rejects an llm step with neither prompt nor prompt_file" do
        step = valid_llm_step
        step.delete("prompt")
        expect { described_class.call(v02_process(steps: [step])) }
          .to raise_error(
            described_class::InvalidDefinition,
            /llm step 'classify' requires either prompt: or prompt_file:, not both/
          )
      end

      it "rejects an llm step missing expected_output_schema" do
        step = valid_llm_step
        step.delete("expected_output_schema")
        expect { described_class.call(v02_process(steps: [step])) }
          .to raise_error(described_class::InvalidDefinition, /expected_output_schema/)
      end

      it "accepts tools: on an automated step and surfaces the value" do
        steps = [ {
          "id" => "do-thing", "name" => "Do thing", "type" => "automated",
          "run" => "scripts/do.rb",
          "tools" => [ "Read", "Grep" ]
        } ]
        result = described_class.call(v02_process(steps: steps))
        expect(result.ok?).to be true
        expect(result.value["process"]["steps"].first["tools"]).to eq([ "Read", "Grep" ])
      end

      it "rejects tools: that is not an array of strings" do
        steps = [ {
          "id" => "do-thing", "name" => "Do thing", "type" => "automated",
          "run" => "scripts/do.rb",
          "tools" => "Read"
        } ]
        expect { described_class.call(v02_process(steps: steps)) }
          .to raise_error(described_class::InvalidDefinition, /tools.*array of non-empty strings/)
      end

      it "accepts a collection output with a valid item_schema" do
        steps = [ {
          "id" => "fetch", "name" => "Fetch", "type" => "automated", "run" => "scripts/fetch.rb",
          "outputs" => [ {
            "name" => "leads", "type" => "object",
            "collection" => true,
            "item_schema" => { "email" => "string", "score" => "number" }
          } ]
        } ]
        result = described_class.call(v02_process(steps: steps))
        expect(result.ok?).to be true
      end

      it "rejects collection: true without item_schema" do
        steps = [ {
          "id" => "fetch", "name" => "Fetch", "type" => "automated", "run" => "scripts/fetch.rb",
          "outputs" => [ { "name" => "leads", "type" => "object", "collection" => true } ]
        } ]
        expect { described_class.call(v02_process(steps: steps)) }
          .to raise_error(
            described_class::InvalidDefinition,
            /output 'leads' has collection: true but no item_schema/
          )
      end

      it "accepts process-level post_review and shared_state_writes passthrough" do
        result = described_class.call(v02_process(
          steps: [],
          extra_process: {
            "post_review" => { "type" => "llm", "model" => "claude-haiku-4-7" },
            "shared_state_writes" => [ "last_run_at", "model_version" ]
          }
        ))
        expect(result.ok?).to be true
        expect(result.value["process"]["shared_state_writes"]).to eq([ "last_run_at", "model_version" ])
      end

      it "rejects post_review that is not a mapping" do
        hash = v02_process(steps: [], extra_process: { "post_review" => "nope" })
        expect { described_class.call(hash) }
          .to raise_error(described_class::InvalidDefinition, /process\.post_review/)
      end
    end
  end
end
