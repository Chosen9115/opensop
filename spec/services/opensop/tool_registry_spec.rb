require "rails_helper"

RSpec.describe Opensop::ToolRegistry do
  before { described_class.reset! }
  after  { described_class.reset! }

  def write_config(dir, body)
    path = File.join(dir, "opensop.config.yaml")
    File.write(path, body)
    path
  end

  describe "built-ins" do
    it "registers the five built-ins even with no config file" do
      Dir.mktmpdir do |dir|
        described_class.load!(File.join(dir, "missing.yaml"))

        expect(described_class.tools.keys).to include("Read", "Grep", "Glob", "Write", "WebFetch")
        expect(described_class.allowed?("Read")).to be true
        expect(described_class.lookup("Read")).to include(handler: "builtin:read_file")
      end
    end

    it "lazily registers built-ins on first access without an explicit load!" do
      described_class.reset!

      expect(described_class.tools.keys).to include("Read", "Grep", "Glob", "Write", "WebFetch")
    end
  end

  describe "with a config file" do
    it "merges a custom Slack tool on top of built-ins" do
      Dir.mktmpdir do |dir|
        path = write_config(dir, <<~YAML)
          tools:
            Slack:
              handler: webhook
              url: https://hooks.slack.com/services/XXX
              description: "Post a message to #ops"
        YAML

        described_class.load!(path)

        expect(described_class.allowed?("Slack")).to be true
        slack = described_class.lookup("Slack")
        expect(slack[:handler]).to eq("webhook")
        expect(slack[:url]).to eq("https://hooks.slack.com/services/XXX")
        # Built-ins are still present.
        expect(described_class.allowed?("Read")).to be true
      end
    end

    it "lets a custom tool override a built-in and logs a warning" do
      Dir.mktmpdir do |dir|
        path = write_config(dir, <<~YAML)
          tools:
            Read:
              handler: webhook
              url: https://example.test/read
              description: "Custom Read override"
        YAML

        expect(Rails.logger).to receive(:warn).with(/overrides built-in/)

        described_class.load!(path)

        read = described_class.lookup("Read")
        expect(read[:handler]).to eq("webhook")
        expect(read[:url]).to eq("https://example.test/read")
      end
    end
  end

  describe ".allowed?" do
    it "returns false for unknown tools" do
      expect(described_class.allowed?("NotARealTool")).to be false
      expect(described_class.lookup("NotARealTool")).to be_nil
    end
  end

  describe ".reset!" do
    it "clears non-built-in entries; built-ins reload on next access" do
      Dir.mktmpdir do |dir|
        path = write_config(dir, <<~YAML)
          tools:
            Slack:
              handler: webhook
              url: https://hooks.slack.com/services/XXX
        YAML
        described_class.load!(path)
        expect(described_class.allowed?("Slack")).to be true

        described_class.reset!

        # Next access lazily reloads — built-ins are back, custom is gone
        # (because reset! cleared the loaded state and the default config
        # path is not the temp file we used above).
        expect(described_class.allowed?("Read")).to be true
        expect(described_class.allowed?("Slack")).to be false
      end
    end
  end
end
