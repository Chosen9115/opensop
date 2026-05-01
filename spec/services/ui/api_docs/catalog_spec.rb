# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ui::ApiDocs::Catalog do
  describe "GUIDES" do
    it "is a frozen array of hashes with :slug and :label" do
      expect(described_class::GUIDES).to be_frozen
      described_class::GUIDES.each do |g|
        expect(g.keys).to include(:slug, :label)
        expect(g[:slug]).to match(/\A[a-z][a-z0-9-]*\z/)
      end
    end

    it "has unique slugs" do
      slugs = described_class::GUIDES.map { |g| g[:slug] }
      expect(slugs).to eq(slugs.uniq)
    end

    it "starts with quickstart so it's the landing page" do
      expect(described_class::GUIDES.first[:slug]).to eq("quickstart")
    end
  end

  describe "ENDPOINT_SECTIONS" do
    it "is a frozen array of section hashes with :key, :label, :endpoints" do
      expect(described_class::ENDPOINT_SECTIONS).to be_frozen
      described_class::ENDPOINT_SECTIONS.each do |s|
        expect(s.keys).to include(:key, :label, :endpoints)
        expect(s[:endpoints]).to be_an(Array)
      end
    end

    it "has every endpoint shaped { slug:, method:, path:, summary_key: }" do
      described_class::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints] }.each do |ep|
        expect(ep.keys).to include(:slug, :method, :path, :summary_key)
        expect(ep[:slug]).to match(/\A[a-z][a-z0-9-]*\z/)
        expect(ep[:method]).to be_in(%w[GET POST DELETE PATCH])
        expect(ep[:path]).to start_with("/sop/")
      end
    end

    it "has globally unique endpoint slugs across all sections" do
      slugs = described_class::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints].map { |e| e[:slug] } }
      expect(slugs).to eq(slugs.uniq)
    end
  end

  describe ".guide" do
    it "returns the guide hash for a known slug" do
      expect(described_class.guide("authentication")).to include(slug: "authentication", label: "Authentication")
    end

    it "returns nil for an unknown slug" do
      expect(described_class.guide("nope")).to be_nil
    end
  end

  describe ".endpoint" do
    it "returns the endpoint hash for a known slug" do
      ep = described_class.endpoint("start-instance")
      expect(ep).to include(slug: "start-instance", method: "POST", path: "/sop/:name/start")
    end

    it "returns nil for an unknown slug" do
      expect(described_class.endpoint("nope")).to be_nil
    end
  end

  describe ".section_for_endpoint" do
    it "returns the section hash containing the endpoint" do
      section = described_class.section_for_endpoint("start-instance")
      expect(section).to include(key: :instances, label: "Instances")
    end

    it "returns nil for an unknown endpoint slug" do
      expect(described_class.section_for_endpoint("nope")).to be_nil
    end
  end

  describe ".guide_slugs" do
    it "returns the flat list of guide slugs in order" do
      expect(described_class.guide_slugs).to eq(described_class::GUIDES.map { |g| g[:slug] })
    end
  end

  describe ".endpoint_slugs" do
    it "returns the flat list of endpoint slugs across all sections" do
      flat = described_class::ENDPOINT_SECTIONS.flat_map { |s| s[:endpoints].map { |e| e[:slug] } }
      expect(described_class.endpoint_slugs).to eq(flat)
    end
  end
end
