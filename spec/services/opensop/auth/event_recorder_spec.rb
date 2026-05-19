require "rails_helper"

RSpec.describe Opensop::Auth::EventRecorder do
  let(:user) { create(:user) }

  # Build a stub request that quacks like ActionDispatch::Request enough
  # for the recorder's two reads: #remote_ip and #user_agent.
  let(:request) do
    instance_double("ActionDispatch::Request",
                    remote_ip: "203.0.113.7",
                    user_agent: "Mozilla/5.0 (test agent)")
  end

  describe ".call" do
    it "creates an AuthEvent populated from the request" do
      event = described_class.call(
        kind: :signed_in,
        user: user,
        request: request,
        metadata: { via: "passkey" }
      )

      expect(event).to be_a(AuthEvent).and be_persisted
      expect(event.kind).to eq("signed_in")
      expect(event.user).to eq(user)
      expect(event.ip_address).to eq("203.0.113.7")
      expect(event.user_agent).to eq("Mozilla/5.0 (test agent)")
      expect(event.metadata).to eq({ "via" => "passkey" })
    end

    it "accepts a nil user (e.g. unknown-email magic link)" do
      event = described_class.call(
        kind: :magic_link_requested,
        user: nil,
        request: request,
        metadata: { email: "ghost@example.com", user_found: false }
      )

      expect(event).to be_persisted
      expect(event.user).to be_nil
    end

    it "works without a request (degrades gracefully)" do
      event = described_class.call(kind: :signed_in, user: user)
      expect(event).to be_persisted
      expect(event.ip_address).to be_nil
      expect(event.user_agent).to eq("")
    end

    it "truncates an oversized user_agent to 255 characters" do
      huge_ua = "x" * 5_000
      huge_request = instance_double("ActionDispatch::Request",
                                     remote_ip: "127.0.0.1",
                                     user_agent: huge_ua)

      event = described_class.call(kind: :signed_in, user: user, request: huge_request)

      expect(event.user_agent.length).to eq(255)
    end

    it "returns nil and logs a warning when persistence fails" do
      allow(AuthEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(AuthEvent.new))
      expect(Rails.logger).to receive(:warn).with(/EventRecorder.+failed to record/)

      result = described_class.call(kind: :signed_in, user: user, request: request)

      expect(result).to be_nil
    end

    it "swallows any unexpected error class without raising" do
      allow(AuthEvent).to receive(:create!).and_raise(StandardError, "boom")
      expect(Rails.logger).to receive(:warn)

      expect {
        described_class.call(kind: :signed_in, user: user, request: request)
      }.not_to raise_error
    end
  end
end
