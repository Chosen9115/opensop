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
  end
end
