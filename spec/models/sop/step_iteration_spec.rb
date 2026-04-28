require 'rails_helper'

RSpec.describe Sop::StepIteration, type: :model do
  describe "validations" do
    it "requires parent_step, index, state, and started_at" do
      iteration = described_class.new
      expect(iteration).not_to be_valid
      expect(iteration.errors[:parent_step]).to be_present
      expect(iteration.errors[:index]).to be_present
      expect(iteration.errors[:started_at]).to be_present
    end
  end

  describe "associations" do
    let(:instance) { create(:sop_instance) }
    let(:parent_step) do
      create(:sop_step, instance: instance, step_type: "loop", step_id: "loop-step")
    end

    it "belongs to a parent_step (Sop::Step)" do
      iteration = described_class.create!(
        parent_step: parent_step,
        index: 0,
        state: "running",
        started_at: Time.current
      )
      expect(iteration.parent_step).to eq(parent_step)
      expect(parent_step.iterations).to include(iteration)
    end

    it "has many body_steps via parent_iteration_id" do
      iteration = described_class.create!(
        parent_step: parent_step,
        index: 0,
        state: "running",
        started_at: Time.current
      )

      body_step = create(
        :sop_step,
        instance: instance,
        step_id: "body-1",
        parent_iteration_id: iteration.id
      )

      expect(iteration.body_steps).to include(body_step)
      expect(body_step.parent_iteration).to eq(iteration)
    end
  end

  describe "state enum" do
    let(:instance) { create(:sop_instance) }
    let(:parent_step) do
      create(:sop_step, instance: instance, step_type: "loop", step_id: "loop-step-2")
    end

    it "exposes prefixed state predicates" do
      iteration = described_class.new(
        parent_step: parent_step,
        index: 0,
        state: "running",
        started_at: Time.current
      )
      expect(iteration.state_running?).to be true
      expect(iteration.state_completed?).to be false

      iteration.state_completed!
      expect(iteration.state_completed?).to be true
      expect(iteration.state_running?).to be false
    end
  end

  describe ".ordered scope" do
    let(:instance) { create(:sop_instance) }
    let(:parent_step) do
      create(:sop_step, instance: instance, step_type: "loop", step_id: "loop-step-3")
    end

    it "sorts by index ascending" do
      now = Time.current
      it2 = described_class.create!(parent_step: parent_step, index: 2, state: "running", started_at: now)
      it0 = described_class.create!(parent_step: parent_step, index: 0, state: "running", started_at: now)
      it1 = described_class.create!(parent_step: parent_step, index: 1, state: "running", started_at: now)

      expect(described_class.where(parent_step: parent_step).ordered).to eq([ it0, it1, it2 ])
    end
  end
end
