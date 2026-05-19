# frozen_string_literal: true

require "rails_helper"
require "view_component/test_helpers"

RSpec.describe KeyValueListComponent, type: :component do
  include ViewComponent::TestHelpers

  # The app's ApplicationController inherits from ActionController::API which
  # has no view_context, so override to a plain Base controller for rendering.
  def vc_test_controller_class
    ActionController::Base
  end

  describe "empty input" do
    it "renders the default empty-state label" do
      result = render_inline(described_class.new(items: {}))

      expect(result.css("details")).to be_empty
      expect(result.text).to include(I18n.t("opensop.common.none"))
    end

    it "renders a custom empty_label when provided" do
      result = render_inline(described_class.new(items: {}, empty_label: "Nothing here"))

      expect(result.text).to include("Nothing here")
    end
  end

  describe "scalar values" do
    it "renders strings, numbers, booleans, and nil as plain divs (no <details>)" do
      items = { "name" => "alice", "age" => 42, "active" => true, "missing" => nil }

      result = render_inline(described_class.new(items: items))

      expect(result.css("details")).to be_empty
      expect(result.text).to include("alice")
      expect(result.text).to include("42")
      expect(result.text).to include(I18n.t("opensop.common.yes"))
      expect(result.text).to include(I18n.t("opensop.common.none"))
    end
  end

  describe "Hash values" do
    let(:items) { { "config" => { "a" => 1, "b" => 2, "c" => 3 } } }

    it "wraps the value in a single collapsed <details> with object summary" do
      result = render_inline(described_class.new(items: items))

      details = result.css("details")
      expect(details.size).to eq(1)
      expect(details.first.attributes).not_to have_key("open")

      summary_text = details.first.at_css("summary").text
      expect(summary_text).to include("JSON object · 3 keys")
    end

    it "renders the pretty-printed JSON inside <pre>" do
      result = render_inline(described_class.new(items: items))

      pre = result.at_css("details pre")
      expect(pre.text).to eq(JSON.pretty_generate(items["config"]))
    end
  end

  describe "Array values" do
    it "wraps arrays in <details> with array-flavored summary" do
      result = render_inline(described_class.new(items: { "tags" => [ "a", "b" ] }))

      details = result.css("details")
      expect(details.size).to eq(1)
      expect(details.first.attributes).not_to have_key("open")

      summary_text = details.first.at_css("summary").text
      expect(summary_text).to include("JSON array · 2 items")
    end
  end

  describe "pluralization" do
    it "uses the singular form when a Hash has one key" do
      result = render_inline(described_class.new(items: { "one_key" => { "k" => "v" } }))

      summary_text = result.at_css("details summary").text
      expect(summary_text).to include("JSON object · 1 key")
      expect(summary_text).not_to include("1 keys")
    end

    it "uses the singular form when an Array has one item" do
      result = render_inline(described_class.new(items: { "tags" => [ "only" ] }))

      summary_text = result.at_css("details summary").text
      expect(summary_text).to include("JSON array · 1 item")
      expect(summary_text).not_to include("1 items")
    end
  end
end
