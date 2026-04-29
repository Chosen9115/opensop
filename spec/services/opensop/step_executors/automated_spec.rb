require 'rails_helper'

RSpec.describe Opensop::StepExecutors::Automated do
  let(:instance) { create(:sop_instance) }
  let(:step) { create(:sop_step, instance: instance, step_type: "automated", inputs: { "alpha" => 1 }) }

  around do |example|
    Dir.mktmpdir do |dir|
      @tmpdir = dir
      example.run
    end
  end

  def write_script(name, body)
    path = File.join(@tmpdir, name)
    File.write(path, body)
    File.chmod(0o755, path)
    path
  end

  describe "#call" do
    it "parses a valid JSON stdout as outputs" do
      script = write_script("ok.rb", <<~RUBY)
        #!/usr/bin/env ruby
        require "json"
        input = JSON.parse(STDIN.read)
        puts JSON.dump({ "echo" => input, "verification_result" => "complete" })
      RUBY

      result = described_class.new.call(step, instance, { "run" => script })

      expect(result[:outputs]).to include("verification_result" => "complete")
      expect(result[:outputs]["echo"]).to eq({ "alpha" => 1 })
    end

    it "raises when the script does not exist" do
      expect {
        described_class.new.call(step, instance, { "run" => "/no/such/path/xyz-#{SecureRandom.hex(4)}.rb" })
      }.to raise_error(described_class::StepFailure, /script not found/)
    end

    it "raises when the script stdout is not JSON" do
      script = write_script("bad.rb", <<~RUBY)
        #!/usr/bin/env ruby
        puts "definitely not json"
      RUBY

      expect {
        described_class.new.call(step, instance, { "run" => script })
      }.to raise_error(described_class::StepFailure, /not valid JSON/)
    end

    it "raises when the JSON output is an array rather than an object" do
      script = write_script("arr.rb", <<~RUBY)
        #!/usr/bin/env ruby
        puts "[1,2,3]"
      RUBY

      expect {
        described_class.new.call(step, instance, { "run" => script })
      }.to raise_error(described_class::StepFailure, /JSON object/)
    end

    it "returns a waiting result when `run:` is blank (external worker pattern)" do
      result = described_class.new.call(step, instance, { "run" => "" })
      expect(result).to eq({ waiting: "waiting_for_worker" })
    end

    describe "v0.2 validation: mode (SPEC-v0.2.md §2.14)" do
      it "is lenient by default — missing declared outputs silently become nil downstream" do
        script = write_script("lenient.rb", <<~RUBY)
          #!/usr/bin/env ruby
          puts "{}"
        RUBY

        result = described_class.new.call(step, instance, {
          "run" => script,
          "outputs" => [
            { "name" => "a", "type" => "string" },
            { "name" => "b", "type" => "string" }
          ]
        })

        expect(result[:outputs]).to eq({})
      end

      it "is also lenient when validation: 'lenient' is explicit" do
        script = write_script("lenient_explicit.rb", <<~RUBY)
          #!/usr/bin/env ruby
          puts "{}"
        RUBY

        result = described_class.new.call(step, instance, {
          "run" => script,
          "validation" => "lenient",
          "outputs" => [
            { "name" => "a", "type" => "string" }
          ]
        })

        expect(result[:outputs]).to eq({})
      end

      it "succeeds in strict mode when every declared output key is present" do
        script = write_script("strict_ok.rb", <<~RUBY)
          #!/usr/bin/env ruby
          require "json"
          puts JSON.dump({ "a" => 1, "b" => 2 })
        RUBY

        result = described_class.new.call(step, instance, {
          "run" => script,
          "validation" => "strict",
          "outputs" => [
            { "name" => "a", "type" => "number" },
            { "name" => "b", "type" => "number" }
          ]
        })

        expect(result[:outputs]).to eq({ "a" => 1, "b" => 2 })
      end

      it "raises in strict mode when a declared output key is missing" do
        script = write_script("strict_missing.rb", <<~RUBY)
          #!/usr/bin/env ruby
          require "json"
          puts JSON.dump({ "a" => 1 })
        RUBY

        expect {
          described_class.new.call(step, instance, {
            "run" => script,
            "validation" => "strict",
            "outputs" => [
              { "name" => "a", "type" => "number" },
              { "name" => "b", "type" => "number" }
            ]
          })
        }.to raise_error(
          described_class::StepFailure,
          /missing declared output\(s\): b/
        )
      end

      it "lists every missing field in the error message and surfaces actual keys" do
        script = write_script("strict_multi_missing.rb", <<~RUBY)
          #!/usr/bin/env ruby
          require "json"
          puts JSON.dump({ "x" => "noise" })
        RUBY

        expect {
          described_class.new.call(step, instance, {
            "run" => script,
            "validation" => "strict",
            "outputs" => [
              { "name" => "a", "type" => "string" },
              { "name" => "b", "type" => "string" }
            ]
          })
        }.to raise_error(described_class::StepFailure) { |err|
          expect(err.message).to match(/missing declared output\(s\): a, b/)
          expect(err.message).to include('"x"')
        }
      end

      it "allows extra keys not declared in outputs: even in strict mode" do
        script = write_script("strict_extras.rb", <<~RUBY)
          #!/usr/bin/env ruby
          require "json"
          puts JSON.dump({ "a" => 1, "debug" => "trace info", "extra" => [ 1, 2, 3 ] })
        RUBY

        result = described_class.new.call(step, instance, {
          "run" => script,
          "validation" => "strict",
          "outputs" => [
            { "name" => "a", "type" => "number" }
          ]
        })

        expect(result[:outputs]).to include("a" => 1, "debug" => "trace info")
      end
    end
  end
end
