require 'rails_helper'

RSpec.describe Sop::Step, type: :model do
  describe "validations" do
    subject { build(:sop_step) }

    it { is_expected.to validate_presence_of(:step_id) }
    it { is_expected.to validate_presence_of(:step_name) }
    it { is_expected.to validate_presence_of(:step_type) }
    it { is_expected.to validate_presence_of(:position) }

    it "requires attempt >= 1" do
      step = build(:sop_step, attempt: 0)
      expect(step).not_to be_valid
      expect(step.errors[:attempt]).to be_present
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:instance).class_name("Sop::Instance").with_foreign_key(:instance_id) }
  end

  describe "enum state" do
    it "exposes predicates" do
      expect(build(:sop_step, state: "active")).to be_active
      expect(build(:sop_step, state: "completed")).to be_completed
    end
  end

  describe "scopes" do
    let(:instance) { create(:sop_instance) }
    let!(:step_two)   { create(:sop_step, instance: instance, position: 2, state: "pending",   step_id: "b") }
    let!(:step_one)   { create(:sop_step, instance: instance, position: 1, state: "active",    step_id: "a") }
    let!(:step_three) { create(:sop_step, instance: instance, position: 3, state: "active",    sub_state: "waiting_for_input", step_id: "c") }

    it ".ordered sorts by position" do
      expect(described_class.ordered).to eq([ step_one, step_two, step_three ])
    end

    it ".active filters on state=active" do
      expect(described_class.active).to contain_exactly(step_one, step_three)
    end

    it ".waiting filters on sub_state" do
      expect(described_class.waiting).to contain_exactly(step_three)
    end
  end
end
