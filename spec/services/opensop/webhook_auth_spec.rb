require "rails_helper"

RSpec.describe Opensop::WebhookAuth do
  let(:secret) { "whsec_test_abc123" }
  let(:body) { '{"type":"BOOKING_CREATED","uid":"bkg_1"}' }

  # Cal.com-style: X-Cal-Signature-256 header with "sha256=<hex>" format.
  def hex_signature(body, secret)
    OpenSSL::HMAC.hexdigest("SHA256", secret, body)
  end

  def base64_signature(body, secret)
    Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", secret, body))
  end

  before { ENV["TEST_WEBHOOK_SECRET"] = secret }
  after  { ENV.delete("TEST_WEBHOOK_SECRET") }

  def config(overrides = {})
    {
      "scheme"          => "hmac-sha256",
      "secret_env"      => "TEST_WEBHOOK_SECRET",
      "header"          => "X-Cal-Signature-256",
      "encoding"        => "hex"
    }.merge(overrides)
  end

  def headers_with(signature, header_name: "X-Cal-Signature-256")
    { header_name => signature }
  end

  describe ".verify!" do
    it "passes for a valid hex signature (no prefix)" do
      sig = hex_signature(body, secret)
      expect {
        described_class.verify!(config: config, headers: headers_with(sig), body: body)
      }.not_to raise_error
    end

    it "passes for a valid hex signature with prefix stripped" do
      sig = "sha256=#{hex_signature(body, secret)}"
      expect {
        described_class.verify!(
          config: config("prefix" => "sha256="),
          headers: headers_with(sig),
          body: body
        )
      }.not_to raise_error
    end

    it "passes for a valid base64 signature" do
      sig = base64_signature(body, secret)
      expect {
        described_class.verify!(
          config: config("encoding" => "base64"),
          headers: headers_with(sig),
          body: body
        )
      }.not_to raise_error
    end

    it "raises InvalidSignature on a mismatched signature" do
      expect {
        described_class.verify!(
          config: config,
          headers: headers_with("deadbeef" * 8),
          body: body
        )
      }.to raise_error(Opensop::WebhookAuth::InvalidSignature, /signature mismatch/)
    end

    it "raises InvalidSignature when the signature header is missing" do
      expect {
        described_class.verify!(config: config, headers: {}, body: body)
      }.to raise_error(Opensop::WebhookAuth::InvalidSignature, /missing X-Cal-Signature-256/)
    end

    it "raises InvalidSignature when the body is tampered with" do
      sig = hex_signature(body, secret)
      tampered = body.sub("BOOKING_CREATED", "BOOKING_CANCELLED")
      expect {
        described_class.verify!(config: config, headers: headers_with(sig), body: tampered)
      }.to raise_error(Opensop::WebhookAuth::InvalidSignature, /mismatch/)
    end

    it "raises MisconfiguredAuth when the secret env var is unset" do
      ENV.delete("TEST_WEBHOOK_SECRET")
      expect {
        described_class.verify!(
          config: config,
          headers: headers_with(hex_signature(body, "anything")),
          body: body
        )
      }.to raise_error(Opensop::WebhookAuth::MisconfiguredAuth, /TEST_WEBHOOK_SECRET/)
    end

    it "raises MisconfiguredAuth on an unsupported scheme" do
      expect {
        described_class.verify!(
          config: config("scheme" => "hmac-md5"),
          headers: headers_with("anything"),
          body: body
        )
      }.to raise_error(Opensop::WebhookAuth::MisconfiguredAuth, /unsupported scheme/)
    end

    it "raises MisconfiguredAuth on an unsupported encoding" do
      expect {
        described_class.verify!(
          config: config("encoding" => "rot13"),
          headers: headers_with("anything"),
          body: body
        )
      }.to raise_error(Opensop::WebhookAuth::MisconfiguredAuth, /unsupported encoding/)
    end
  end
end
