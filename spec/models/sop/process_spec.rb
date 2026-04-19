require 'rails_helper'

RSpec.describe Sop::Process, type: :model do
  describe "validations" do
    subject { build(:sop_process) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:version) }
    it { is_expected.to validate_uniqueness_of(:name).scoped_to(:version) }
  end

  describe "associations" do
    it { is_expected.to have_many(:instances).class_name("Sop::Instance").with_foreign_key(:process_id) }
  end

  describe "enum status" do
    it "exposes enum predicates" do
      process = build(:sop_process, status: "active")
      expect(process).to be_active
    end

    it "persists the enum value as its string" do
      process = create(:sop_process, status: "deprecated")
      raw_status = Sop::Process.connection.select_value(
        "select status from sop_processes where id = '#{process.id}'"
      )
      expect(raw_status).to eq("deprecated")
    end
  end

  describe ".published scope" do
    it "returns only active processes" do
      active = create(:sop_process, status: "active")
      create(:sop_process, :deprecated)
      create(:sop_process, :archived)

      expect(described_class.published).to contain_exactly(active)
    end
  end

  describe "factory" do
    it "is valid" do
      expect(build(:sop_process)).to be_valid
    end

    it "allows same name with a different version" do
      create(:sop_process, name: "dup-check", version: "1.0")
      expect(build(:sop_process, name: "dup-check", version: "2.0")).to be_valid
    end

    it "rejects a duplicate name+version pair" do
      create(:sop_process, name: "dup-check", version: "1.0")
      dup = build(:sop_process, name: "dup-check", version: "1.0")
      expect(dup).not_to be_valid
    end
  end
end
