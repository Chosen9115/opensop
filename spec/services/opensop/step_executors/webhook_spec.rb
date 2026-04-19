require 'rails_helper'

RSpec.describe Opensop::StepExecutors::Webhook do
  let(:instance) { create(:sop_instance) }
  let(:step) { create(:sop_step, instance: instance, step_type: "webhook", step_id: "compliance-check") }

  it "creates a pending callback row and returns waiting_for_callback" do
    definition = {
      "webhook" => {
        "method" => "POST",
        "url" => "https://example.com/endpoint",
        "response_mode" => "callback",
        "poll_timeout" => "7d"
      }
    }

    result = described_class.new.call(step, instance, definition)

    expect(result).to eq({ waiting: "waiting_for_callback" })

    callback = instance.callbacks.find_by(step_id: "compliance-check")
    expect(callback).to be_present
    expect(callback.status).to eq("pending")
    expect(callback.callback_path).to match(%r{\A/sop/webhooks/[0-9a-f-]{36}\z})
    expect(callback.expires_at).to be_within(5.minutes).of(7.days.from_now)
    expect(instance.events.where(event_type: "step.webhook_registered")).to exist
  end

  it "creates a callback with no expiration when no timeout is set" do
    result = described_class.new.call(step, instance, {
      "webhook" => { "method" => "POST", "url" => "x", "response_mode" => "callback" }
    })

    expect(result).to eq({ waiting: "waiting_for_callback" })
    callback = instance.callbacks.last
    expect(callback.expires_at).to be_nil
  end
end
