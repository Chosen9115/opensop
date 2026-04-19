require 'rails_helper'

RSpec.describe Opensop::StepExecutors::Notification do
  it "returns immediate outputs with notified:true" do
    instance = create(:sop_instance)
    step = create(:sop_step, instance: instance, step_type: "notification")

    result = described_class.new.call(step, instance, {})
    expect(result[:outputs]).to include("notified" => true)
  end
end
