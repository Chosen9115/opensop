require 'rails_helper'

RSpec.describe Opensop::Templating do
  describe ".render" do
    it "returns the input unchanged when no placeholders are present" do
      expect(described_class.render("https://example.test/entities")).to eq("https://example.test/entities")
    end

    it "returns nil for nil input" do
      expect(described_class.render(nil)).to be_nil
    end

    it "returns non-strings untouched" do
      expect(described_class.render(42)).to eq(42)
    end

    it "substitutes callback_url literally" do
      rendered = described_class.render(
        "callback at ${callback_url} please",
        callback_url: "http://localhost:3000/sop/webhooks/abc-123"
      )
      expect(rendered).to eq("callback at http://localhost:3000/sop/webhooks/abc-123 please")
    end

    it "substitutes env variables via ${env.X}" do
      ENV["COMPLIANCE_PROVIDER_URL"] = "https://provider.test"
      begin
        expect(described_class.render("${env.COMPLIANCE_PROVIDER_URL}/entities"))
          .to eq("https://provider.test/entities")
      ensure
        ENV.delete("COMPLIANCE_PROVIDER_URL")
      end
    end

    it "raises when an env variable is not set" do
      expect { described_class.render("${env.DEFINITELY_NOT_SET_12345}") }
        .to raise_error(Opensop::Templating::MissingVariable, /DEFINITELY_NOT_SET_12345/)
    end

    it "substitutes process.inputs.X" do
      rendered = described_class.render(
        "country=${process.inputs.country}",
        process_inputs: { "country" => "MX" }
      )
      expect(rendered).to eq("country=MX")
    end

    it "substitutes bare paths from step inputs" do
      rendered = described_class.render(
        "entity=${business_record.legal_name}",
        step_inputs: { "business_record" => { "legal_name" => "Acme SA" } }
      )
      expect(rendered).to eq("entity=Acme SA")
    end

    it "stringifies numbers, booleans, and hashes" do
      rendered = described_class.render(
        "amt=${amount} flag=${active} meta=${meta}",
        step_inputs: { "amount" => 5000, "active" => true, "meta" => { "tier" => "pro" } }
      )
      expect(rendered).to eq('amt=5000 flag=true meta={"tier":"pro"}')
    end

    it "raises a clear error when a bare path is missing" do
      expect {
        described_class.render("${missing_key}", step_inputs: { "other" => 1 })
      }.to raise_error(Opensop::Templating::MissingVariable, /missing_key/)
    end

    it "raises when descending into a non-hash" do
      expect {
        described_class.render("${foo.bar}", step_inputs: { "foo" => "not a hash" })
      }.to raise_error(Opensop::Templating::MissingVariable, /cannot descend/)
    end

    it "handles multiple placeholders in one string" do
      rendered = described_class.render(
        "${callback_url}?country=${process.inputs.country}&id=${id}",
        process_inputs: { "country" => "US" },
        step_inputs:    { "id" => "abc-123" },
        callback_url:   "http://localhost/cb"
      )
      expect(rendered).to eq("http://localhost/cb?country=US&id=abc-123")
    end
  end
end
