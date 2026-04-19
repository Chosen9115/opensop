require 'rails_helper'

RSpec.describe Sop::Instance, type: :model do
  describe "validations" do
    subject { build(:sop_instance) }

    it { is_expected.to validate_presence_of(:process_name) }
    it { is_expected.to validate_presence_of(:process_version) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:process).class_name("Sop::Process").optional }
    it { is_expected.to have_many(:steps).class_name("Sop::Step").with_foreign_key(:instance_id) }
    it { is_expected.to have_many(:events).class_name("Sop::Event").with_foreign_key(:instance_id) }
    it { is_expected.to have_many(:callbacks).class_name("Sop::Callback").with_foreign_key(:instance_id) }
  end

  describe "enum state" do
    it "exposes predicates" do
      expect(build(:sop_instance, state: "running")).to be_running
      expect(build(:sop_instance, state: "completed")).to be_completed
    end
  end

  describe "steps ordering" do
    it "returns steps ordered by position ascending" do
      instance = create(:sop_instance)
      last  = create(:sop_step, instance: instance, position: 3, step_id: "c")
      first = create(:sop_step, instance: instance, position: 1, step_id: "a")
      middle = create(:sop_step, instance: instance, position: 2, step_id: "b")

      expect(instance.steps).to eq([ first, middle, last ])
    end
  end

  describe "scopes" do
    let!(:pending)   { create(:sop_instance, state: "pending") }
    let!(:running)   { create(:sop_instance, :running) }
    let!(:completed) { create(:sop_instance, :completed) }
    let!(:failed)    { create(:sop_instance, :failed) }
    let!(:cancelled) { create(:sop_instance, :cancelled) }

    it ".active returns pending + running" do
      expect(described_class.active).to contain_exactly(pending, running)
    end

    it ".terminal returns completed + failed + cancelled" do
      expect(described_class.terminal).to contain_exactly(completed, failed, cancelled)
    end
  end
end
