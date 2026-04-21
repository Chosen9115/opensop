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

    context "with ${payload.X.Y.Z} references" do
      let(:cal_payload) do
        {
          "type" => "BOOKING_CREATED",
          "startTime" => "2026-05-01T15:00:00Z",
          "attendees" => [
            { "email" => "ana@example.com", "name" => "Ana García" },
            { "email" => "second@example.com", "name" => "Second Guest" }
          ],
          "eventType" => { "title" => "Intro call" }
        }
      end

      it "walks nested payload paths" do
        expect(described_class.render("${payload.eventType.title}", payload: cal_payload))
          .to eq("Intro call")
      end

      it "supports integer indices on arrays" do
        rendered = described_class.render(
          "${payload.attendees.0.email} and ${payload.attendees.1.name}",
          payload: cal_payload
        )
        expect(rendered).to eq("ana@example.com and Second Guest")
      end

      it "raises when an array index is out of bounds" do
        expect {
          described_class.render("${payload.attendees.5.email}", payload: cal_payload)
        }.to raise_error(Opensop::Templating::MissingVariable, /out of bounds/)
      end

      it "raises when an array index is non-integer" do
        expect {
          described_class.render("${payload.attendees.first.email}", payload: cal_payload)
        }.to raise_error(Opensop::Templating::MissingVariable, /non-integer/)
      end
    end
  end

  describe ".resolve_value" do
    let(:payload) { { "amount" => 5000, "flags" => { "vip" => true }, "tags" => %w[a b] } }

    it "returns the raw numeric value for a whole-expression input" do
      expect(described_class.resolve_value("${payload.amount}", payload: payload)).to eq(5000)
    end

    it "returns the raw boolean value" do
      expect(described_class.resolve_value("${payload.flags.vip}", payload: payload)).to be(true)
    end

    it "returns the raw array value" do
      expect(described_class.resolve_value("${payload.tags}", payload: payload)).to eq(%w[a b])
    end

    it "string-substitutes when the value has mixed content" do
      expect(described_class.resolve_value("#{payload["amount"]} cents", payload: payload))
        .to eq("5000 cents")
    end

    it "returns literal strings unchanged" do
      expect(described_class.resolve_value("cal.com", payload: payload)).to eq("cal.com")
    end

    it "returns non-string values (Integer/Hash literals from YAML) unchanged" do
      expect(described_class.resolve_value(42)).to eq(42)
      expect(described_class.resolve_value({ "nested" => true })).to eq({ "nested" => true })
    end

    it "raises on missing payload path" do
      expect {
        described_class.resolve_value("${payload.missing.field}", payload: payload)
      }.to raise_error(Opensop::Templating::MissingVariable, /missing/)
    end
  end
end
