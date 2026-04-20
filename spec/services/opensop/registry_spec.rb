require 'rails_helper'

RSpec.describe Opensop::Registry do
  def write_yaml(dir, name, definition)
    path = File.join(dir, "#{name}.sop.yaml")
    File.write(path, YAML.dump(definition))
    path
  end

  def sample_definition(name: "sample-proc", version: "1.0", steps: [])
    {
      "opensop" => "0.1",
      "process" => {
        "name" => name,
        "version" => version,
        "description" => "desc",
        "owner" => "team",
        "tags" => [ "alpha" ],
        "steps" => steps
      }
    }
  end

  describe ".load_file" do
    it "creates a Sop::Process record from a YAML file" do
      Dir.mktmpdir do |dir|
        path = write_yaml(dir, "sample-proc", sample_definition)

        record = described_class.load_file(path)

        expect(record).to be_persisted
        expect(record.name).to eq("sample-proc")
        expect(record.version).to eq("1.0")
        expect(record.status).to eq("active")
        expect(record.definition.dig("process", "name")).to eq("sample-proc")
      end
    end

    it "updates an existing record when the definition changes" do
      Dir.mktmpdir do |dir|
        path = write_yaml(dir, "sample-proc", sample_definition)
        original = described_class.load_file(path)

        new_def = sample_definition
        new_def["process"]["description"] = "updated desc"
        File.write(path, YAML.dump(new_def))

        updated = described_class.load_file(path)

        expect(updated.id).to eq(original.id)
        expect(updated.description).to eq("updated desc")
      end
    end
  end

  describe ".load_all" do
    it "loads the real customer-onboarding definition" do
      path = Rails.root.join("processes")
      records = described_class.load_all(path)

      expect(records).not_to be_empty
      names = records.map(&:name)
      expect(names).to include("customer-onboarding")
    end

    it "is idempotent (does not create duplicates on re-run)" do
      Dir.mktmpdir do |dir|
        write_yaml(dir, "sample-proc", sample_definition)

        expect {
          2.times { described_class.load_all(dir) }
        }.to change(Sop::Process, :count).by(1)
      end
    end

    it "returns [] when path does not exist" do
      expect(described_class.load_all("/nonexistent/path/#{SecureRandom.hex(4)}")).to eq([])
    end

    # The public repo ships examples under processes/examples/, and downstream
    # forks add private processes under processes/<their-org>/ (gitignored in
    # public). Both must load equivalently because the engine globs recursively.
    context "with processes in multiple sibling subdirectories" do
      it "loads YAML files from every nested subdirectory" do
        Dir.mktmpdir do |base|
          examples_dir = File.join(base, "examples")
          private_dir  = File.join(base, "coba")
          FileUtils.mkdir_p(examples_dir)
          FileUtils.mkdir_p(private_dir)

          write_yaml(examples_dir, "public-proc",  sample_definition(name: "public-proc"))
          write_yaml(private_dir,  "private-proc", sample_definition(name: "private-proc"))

          records = described_class.load_all(base)

          expect(records.map(&:name)).to contain_exactly("public-proc", "private-proc")
        end
      end

      it "ignores empty sibling directories" do
        Dir.mktmpdir do |base|
          examples_dir = File.join(base, "examples")
          empty_dir    = File.join(base, "coba")
          FileUtils.mkdir_p(examples_dir)
          FileUtils.mkdir_p(empty_dir)

          write_yaml(examples_dir, "public-proc", sample_definition(name: "public-proc"))

          records = described_class.load_all(base)

          expect(records.map(&:name)).to eq([ "public-proc" ])
        end
      end

      it "loads processes from arbitrarily named subdirectories (no hardcoded list)" do
        Dir.mktmpdir do |base|
          %w[examples coba acme-corp team-x].each do |subdir|
            FileUtils.mkdir_p(File.join(base, subdir))
            write_yaml(File.join(base, subdir), "#{subdir}-proc", sample_definition(name: "#{subdir}-proc"))
          end

          records = described_class.load_all(base)

          expect(records.map(&:name)).to contain_exactly(
            "examples-proc", "coba-proc", "acme-corp-proc", "team-x-proc"
          )
        end
      end
    end
  end
end
