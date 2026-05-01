# frozen_string_literal: true

require "rails_helper"
require "view_component/test_helpers"

RSpec.describe Ui::ApiDocs::CodePanelComponent, type: :component do
  include ViewComponent::TestHelpers

  def vc_test_controller_class
    ActionController::Base
  end

  describe "single-body mode" do
    it "renders the body inside a <pre> with the source target for the copy controller" do
      result = render_inline(described_class.new(label: "REQUEST BODY · application/json")) do |c|
        c.with_body { "{ \"hello\": \"world\" }" }
      end

      pre = result.at_css("pre[data-api-docs--copy-target='source']")
      expect(pre).not_to be_nil
      expect(pre.text).to include("hello")
    end

    it "renders the static label in the header" do
      result = render_inline(described_class.new(label: "REQUEST BODY · application/json")) do |c|
        c.with_body { "{}" }
      end

      expect(result.text).to include("REQUEST BODY · application/json")
    end

    it "does not render tab buttons when in single-body mode" do
      result = render_inline(described_class.new(label: "X")) do |c|
        c.with_body { "code" }
      end

      expect(result.css("button[data-api-docs--code-tabs-target='tab']")).to be_empty
    end
  end

  describe "tabbed mode" do
    it "renders one button per tab and one pane per pane slot" do
      tabs = [[:curl, "curl"], [:node, "node"]]
      result = render_inline(described_class.new(tabs: tabs)) do |panel|
        panel.with_pane(key: :curl) { "curl ..." }
        panel.with_pane(key: :node) { "fetch(...)" }
      end

      buttons = result.css("button[data-api-docs--code-tabs-target='tab']")
      expect(buttons.size).to eq(2)
      expect(buttons.map { |b| b[:'data-tab-key'] }).to eq(%w[curl node])

      panes = result.css("div[data-api-docs--code-tabs-target='pane']")
      expect(panes.size).to eq(2)
      expect(panes.map { |p| p[:'data-pane-key'] }).to eq(%w[curl node])
    end

    it "wires the controller attribute on the root element" do
      tabs = [[:curl, "curl"]]
      result = render_inline(described_class.new(tabs: tabs)) do |panel|
        panel.with_pane(key: :curl) { "curl ..." }
      end

      root = result.at_css("div[data-controller='api-docs--code-tabs']")
      expect(root).not_to be_nil
    end

    it "marks the first tab active and shows only the first pane by default" do
      tabs = [[:curl, "curl"], [:node, "node"]]
      result = render_inline(described_class.new(tabs: tabs)) do |panel|
        panel.with_pane(key: :curl) { "curl" }
        panel.with_pane(key: :node) { "node" }
      end

      first_btn, second_btn = result.css("button[data-api-docs--code-tabs-target='tab']").to_a
      expect(first_btn[:class]).to include("bg-[#1a1d24]")
      expect(first_btn[:class]).to include("text-white")
      expect(second_btn[:class]).not_to include("bg-[#1a1d24]")

      first_pane, second_pane = result.css("div[data-api-docs--code-tabs-target='pane']").to_a
      expect(first_pane[:class] || "").not_to include("hidden")
      expect(second_pane[:class]).to include("hidden")
    end
  end

  describe "status pill" do
    it "renders a green 200 pill" do
      result = render_inline(described_class.new(status: { code: 200, label: "RESPONSE" })) do |c|
        c.with_body { "{}" }
      end

      pill = result.css("span").find { |s| s.text.strip == "200" }
      expect(pill).not_to be_nil
      expect(pill[:class]).to include("bg-[#e7f6ec]")
      expect(pill[:class]).to include("text-[#0f7a3d]")
      expect(result.text).to include("RESPONSE")
    end

    it "renders a yellow 422 pill" do
      result = render_inline(described_class.new(status: { code: 422, label: "RESPONSE" })) do |c|
        c.with_body { "{}" }
      end

      pill = result.css("span").find { |s| s.text.strip == "422" }
      expect(pill[:class]).to include("bg-[#fdf3d6]")
      expect(pill[:class]).to include("text-[#946700]")
    end

    it "renders a red 500 pill" do
      result = render_inline(described_class.new(status: { code: 500, label: "RESPONSE" })) do |c|
        c.with_body { "{}" }
      end

      pill = result.css("span").find { |s| s.text.strip == "500" }
      expect(pill[:class]).to include("bg-[#fbe9e9]")
      expect(pill[:class]).to include("text-[#b03333]")
    end

    it "uses neutral styling for an unmapped status code" do
      result = render_inline(described_class.new(status: { code: 418, label: "RESPONSE" })) do |c|
        c.with_body { "{}" }
      end

      pill = result.css("span").find { |s| s.text.strip == "418" }
      expect(pill[:class]).to include("bg-[#eef0f3]")
    end
  end

  describe "copy button" do
    it "is rendered by default and wired to the copy stimulus controller" do
      result = render_inline(described_class.new(label: "X")) do |c|
        c.with_body { "code" }
      end

      btn = result.at_css("button[data-controller='api-docs--copy']")
      expect(btn).not_to be_nil
      expect(btn[:'data-action']).to eq("click->api-docs--copy#copy")
      expect(btn.text).to include("Copy")
    end

    it "is omitted when copyable: false" do
      result = render_inline(described_class.new(label: "X", copyable: false)) do |c|
        c.with_body { "code" }
      end

      expect(result.css("button[data-controller='api-docs--copy']")).to be_empty
    end
  end
end
