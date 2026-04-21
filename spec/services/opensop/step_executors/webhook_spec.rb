require 'rails_helper'

RSpec.describe Opensop::StepExecutors::Webhook do
  let(:instance) do
    create(:sop_instance, inputs: { "country" => "MX" })
  end
  let(:step) do
    create(:sop_step,
           instance: instance,
           step_type: "webhook",
           step_id: "compliance-check",
           inputs: { "business_record" => { "legal_name" => "Acme SA", "rfc" => "ACM010101AAA" } })
  end

  def definition(overrides = {})
    {
      "webhook" => {
        "method" => "POST",
        "url" => "https://provider.test/entities",
        "response_mode" => "callback",
        "poll_timeout" => "7d"
      }.merge(overrides)
    }
  end

  describe "callback mode" do
    it "fires the outbound request, persists a callback row, and returns waiting_for_callback" do
      stub = stub_request(:post, "https://provider.test/entities")
             .to_return(status: 202, body: "{\"accepted\":true}")

      result = described_class.new.call(step, instance, definition)

      expect(result).to eq({ waiting: "waiting_for_callback" })
      expect(stub).to have_been_requested

      callback = instance.callbacks.find_by(step_id: "compliance-check")
      expect(callback).to be_present
      expect(callback.status).to eq("pending")
      expect(callback.callback_path).to match(%r{\A/sop/webhooks/[0-9a-f-]{36}\z})
      expect(callback.expires_at).to be_within(5.minutes).of(7.days.from_now)
      expect(instance.events.where(event_type: "step.webhook_dispatched")).to exist
    end

    it "injects ${callback_url} into the body so providers know where to reply" do
      body_received = nil
      stub_request(:post, "https://provider.test/entities")
        .to_return(status: 200, body: "{}")
        .with { |req| body_received = req.body; true }

      body_path = Rails.root.join("spec/fixtures/webhook_body.json")
      FileUtils.mkdir_p(body_path.dirname)
      File.write(body_path, '{"callback": "${callback_url}", "entity": "${business_record.legal_name}"}')

      described_class.new.call(step, instance, definition(
        "body_template" => body_path.to_s
      ))

      parsed = JSON.parse(body_received)
      expect(parsed["callback"]).to match(%r{http://localhost:3000/sop/webhooks/[0-9a-f-]{36}})
      expect(parsed["entity"]).to eq("Acme SA")

      File.delete(body_path) if File.exist?(body_path)
    end

    it "destroys the callback row and raises if the outbound request fails" do
      stub_request(:post, "https://provider.test/entities").to_return(status: 500, body: "oops")

      expect {
        described_class.new.call(step, instance, definition)
      }.to raise_error(Opensop::StepExecutors::Webhook::StepFailure, /HTTP 500/)

      expect(instance.callbacks.count).to eq(0)
    end

    it "destroys the callback row and raises on connection failure" do
      stub_request(:post, "https://provider.test/entities").to_raise(SocketError.new("getaddrinfo"))

      expect {
        described_class.new.call(step, instance, definition)
      }.to raise_error(Opensop::StepExecutors::Webhook::StepFailure, /outbound request failed/)

      expect(instance.callbacks.count).to eq(0)
    end

    it "creates a callback with no expiration when no timeout is set" do
      stub_request(:post, "https://provider.test/entities").to_return(status: 200, body: "{}")

      described_class.new.call(step, instance, definition("poll_timeout" => nil))

      expect(instance.callbacks.last.expires_at).to be_nil
    end
  end

  describe "sync mode" do
    it "returns the JSON response body as step outputs" do
      stub_request(:post, "https://provider.test/score")
        .to_return(status: 200, body: '{"score": 0.87, "tier": "gold"}')

      result = described_class.new.call(step, instance, {
        "webhook" => {
          "method" => "POST",
          "url" => "https://provider.test/score",
          "response_mode" => "sync"
        }
      })

      expect(result[:outputs]).to eq({ "score" => 0.87, "tier" => "gold" })
      expect(instance.callbacks.count).to eq(0)
    end

    it "raises StepFailure on non-2xx response" do
      stub_request(:post, "https://provider.test/score").to_return(status: 422, body: "bad")

      expect {
        described_class.new.call(step, instance, {
          "webhook" => {
            "method" => "POST",
            "url" => "https://provider.test/score",
            "response_mode" => "sync"
          }
        })
      }.to raise_error(Opensop::StepExecutors::Webhook::StepFailure, /HTTP 422/)
    end

    it "raises if the response is not valid JSON" do
      stub_request(:post, "https://provider.test/score").to_return(status: 200, body: "<html>not json</html>")

      expect {
        described_class.new.call(step, instance, {
          "webhook" => {
            "method" => "POST",
            "url" => "https://provider.test/score",
            "response_mode" => "sync"
          }
        })
      }.to raise_error(Opensop::StepExecutors::Webhook::StepFailure, /not valid JSON/)
    end
  end

  describe "URL and header interpolation" do
    it "substitutes ${env.X} in the URL" do
      ENV["PROVIDER_URL"] = "https://interpolated.test"
      begin
        stub = stub_request(:post, "https://interpolated.test/endpoint").to_return(status: 200, body: "{}")

        described_class.new.call(step, instance, {
          "webhook" => {
            "method" => "POST",
            "url" => "${env.PROVIDER_URL}/endpoint",
            "response_mode" => "sync"
          }
        })

        expect(stub).to have_been_requested
      ensure
        ENV.delete("PROVIDER_URL")
      end
    end

    it "substitutes variables in header values" do
      ENV["PROVIDER_KEY"] = "sk_test_xxx"
      begin
        stub = stub_request(:post, "https://provider.test/endpoint")
               .with(headers: { "Authorization" => "Bearer sk_test_xxx" })
               .to_return(status: 200, body: "{}")

        described_class.new.call(step, instance, {
          "webhook" => {
            "method" => "POST",
            "url" => "https://provider.test/endpoint",
            "headers" => { "Authorization" => "Bearer ${env.PROVIDER_KEY}" },
            "response_mode" => "sync"
          }
        })

        expect(stub).to have_been_requested
      ensure
        ENV.delete("PROVIDER_KEY")
      end
    end

    it "raises on an unset env variable in URL" do
      expect {
        described_class.new.call(step, instance, {
          "webhook" => {
            "method" => "POST",
            "url" => "${env.DEFINITELY_NOT_SET_98765}/endpoint",
            "response_mode" => "sync"
          }
        })
      }.to raise_error(Opensop::StepExecutors::Webhook::StepFailure, /template error.*DEFINITELY_NOT_SET_98765/)
    end
  end

  describe "validation" do
    it "rejects an unknown response_mode" do
      expect {
        described_class.new.call(step, instance, {
          "webhook" => { "method" => "POST", "url" => "https://x.test", "response_mode" => "magical" }
        })
      }.to raise_error(Opensop::StepExecutors::Webhook::StepFailure, /unknown response_mode/)
    end

    it "rejects an unsupported HTTP method" do
      expect {
        described_class.new.call(step, instance, {
          "webhook" => { "method" => "TRACE", "url" => "https://x.test", "response_mode" => "sync" }
        })
      }.to raise_error(Opensop::StepExecutors::Webhook::StepFailure, /unsupported HTTP method/)
    end

    it "rejects poll mode as unimplemented" do
      expect {
        described_class.new.call(step, instance, {
          "webhook" => { "method" => "POST", "url" => "https://x.test", "response_mode" => "poll" }
        })
      }.to raise_error(Opensop::StepExecutors::Webhook::StepFailure, /poll is not implemented/)
    end

    it "rejects a missing body_template file" do
      stub_request(:post, "https://provider.test/endpoint").to_return(status: 200, body: "{}")

      expect {
        described_class.new.call(step, instance, {
          "webhook" => {
            "method" => "POST",
            "url" => "https://provider.test/endpoint",
            "response_mode" => "sync",
            "body_template" => "./missing/file.json"
          }
        })
      }.to raise_error(Opensop::StepExecutors::Webhook::StepFailure, /body_template not found/)
    end
  end
end
