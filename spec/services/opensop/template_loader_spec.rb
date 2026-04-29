require "rails_helper"
require "tmpdir"
require "pathname"
require "fileutils"

RSpec.describe Opensop::TemplateLoader do
  describe ".call" do
    context "when the root directory does not exist" do
      it "returns an empty array" do
        Dir.mktmpdir do |tmp|
          missing = Pathname.new(tmp).join("does-not-exist")
          expect(described_class.call(root: missing)).to eq([])
        end
      end
    end

    context "when the root directory is empty" do
      it "returns an empty array" do
        Dir.mktmpdir do |tmp|
          expect(described_class.call(root: tmp)).to eq([])
        end
      end
    end

    context "with valid .sop.yaml files" do
      it "loads each template with normalized metadata" do
        Dir.mktmpdir do |tmp|
          File.write(File.join(tmp, "alpha.sop.yaml"), <<~YAML)
            opensop: "0.1"
            process:
              name: "alpha"
              version: "1.0"
              description: "Alpha description"
              inputs:
                - name: "x"
                - name: "y"
              outputs:
                - name: "z"
              steps:
                - id: "s1"
                - id: "s2"
                - id: "s3"
          YAML

          File.write(File.join(tmp, "beta.sop.yaml"), <<~YAML)
            opensop: "0.1"
            process:
              name: "beta"
              version: "0.2"
              description: "Beta description"
              inputs: []
              outputs: []
              steps:
                - id: "only"
          YAML

          result = described_class.call(root: tmp)

          expect(result.size).to eq(2)

          alpha = result.find { |t| t[:name] == "alpha" }
          expect(alpha[:version]).to eq("1.0")
          expect(alpha[:description]).to eq("Alpha description")
          expect(alpha[:inputs_count]).to eq(2)
          expect(alpha[:outputs_count]).to eq(1)
          expect(alpha[:steps_count]).to eq(3)
          expect(alpha[:raw_yaml]).to include("name: \"alpha\"")
          expect(alpha[:path]).to end_with("alpha.sop.yaml")

          beta = result.find { |t| t[:name] == "beta" }
          expect(beta[:steps_count]).to eq(1)
          expect(beta[:inputs_count]).to eq(0)
          expect(beta[:outputs_count]).to eq(0)
        end
      end

      it "sorts results deterministically by path" do
        Dir.mktmpdir do |tmp|
          %w[zeta alpha mango].each do |name|
            File.write(File.join(tmp, "#{name}.sop.yaml"), <<~YAML)
              process:
                name: "#{name}"
                version: "1.0"
            YAML
          end

          names = described_class.call(root: tmp).map { |t| t[:name] }
          expect(names).to eq(%w[alpha mango zeta])
        end
      end

      it "recurses into subdirectories" do
        Dir.mktmpdir do |tmp|
          FileUtils.mkdir_p(File.join(tmp, "nested/deeper"))
          File.write(File.join(tmp, "nested/deeper/leaf.sop.yaml"), <<~YAML)
            process:
              name: "leaf"
              version: "0.1"
          YAML

          result = described_class.call(root: tmp)
          expect(result.size).to eq(1)
          expect(result.first[:name]).to eq("leaf")
        end
      end
    end

    context "when a file is malformed" do
      it "skips bad YAML and logs a warning" do
        Dir.mktmpdir do |tmp|
          File.write(File.join(tmp, "good.sop.yaml"), <<~YAML)
            process:
              name: "good"
              version: "1.0"
          YAML
          File.write(File.join(tmp, "bad.sop.yaml"), "::: not yaml :::\n  -- broken")

          logger = instance_double(Logger, warn: nil)
          result = described_class.call(root: tmp, logger: logger)

          expect(result.size).to eq(1)
          expect(result.first[:name]).to eq("good")
          expect(logger).to have_received(:warn).with(/bad\.sop\.yaml/)
        end
      end

      it "skips files that are not a YAML mapping" do
        Dir.mktmpdir do |tmp|
          File.write(File.join(tmp, "list.sop.yaml"), "- one\n- two\n")

          logger = instance_double(Logger, warn: nil)
          result = described_class.call(root: tmp, logger: logger)

          expect(result).to eq([])
          expect(logger).to have_received(:warn).with(/not a YAML mapping/)
        end
      end

      it "skips files missing the process: block" do
        Dir.mktmpdir do |tmp|
          File.write(File.join(tmp, "noproc.sop.yaml"), "opensop: \"0.1\"\n")

          logger = instance_double(Logger, warn: nil)
          result = described_class.call(root: tmp, logger: logger)

          expect(result).to eq([])
          expect(logger).to have_received(:warn).with(/missing process/)
        end
      end
    end
  end
end
