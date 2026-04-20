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
  end
end
