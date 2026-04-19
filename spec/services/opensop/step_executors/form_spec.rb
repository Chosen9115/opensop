require 'rails_helper'

RSpec.describe Opensop::StepExecutors::Form do
  it "returns waiting_for_input" do
    instance = create(:sop_instance)
    step = create(:sop_step, instance: instance, step_type: "form")

    expect(described_class.new.call(step, instance, {})).to eq({ waiting: "waiting_for_input" })
  end
end
