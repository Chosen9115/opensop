# frozen_string_literal: true

require "rails_helper"
require "view_component/test_helpers"

RSpec.describe Ui::ApiDocs::CalloutComponent, type: :component do
  include ViewComponent::TestHelpers

  # ApplicationController inherits from ActionController::API; override to a
  # plain Base so ViewComponent has a view_context to render in.
  def vc_test_controller_class
    ActionController::Base
  end

  describe "info variant (default)" do
    it "renders the info background and left border" do
      result = render_inline(described_class.new) do |c|
        c.with_body { "Body content" }
      end

      root = result.at_css("div")
      expect(root[:class]).to include("bg-[#eef4ff]")
      expect(root[:class]).to include("border-[#1f4ed8]")
    end

    it "renders the body slot content" do
      result = render_inline(described_class.new) do |c|
        c.with_body { "Body content" }
      end

      expect(result.text).to include("Body content")
    end

    it "renders the label in the info color when provided" do
      result = render_inline(described_class.new(label: "AUTH")) do |c|
        c.with_body { "Body content" }
      end

      label_span = result.css("span").find { |s| s.text.strip == "AUTH" }
      expect(label_span).not_to be_nil
      expect(label_span[:class]).to include("text-[#1f4ed8]")
      expect(label_span[:class]).to include("uppercase")
    end

    it "omits the label and dash when no label is provided" do
      result = render_inline(described_class.new) do |c|
        c.with_body { "Body content" }
      end

      expect(result.text).not_to include("—")
    end
  end

  describe "warn variant" do
    it "renders the warn background and left border" do
      result = render_inline(described_class.new(variant: :warn, label: "IMPORTANT")) do |c|
        c.with_body { "Heads up" }
      end

      root = result.at_css("div")
      expect(root[:class]).to include("bg-[#fdf3d680]")
      expect(root[:class]).to include("border-[#946700]")

      label_span = result.css("span").find { |s| s.text.strip == "IMPORTANT" }
      expect(label_span[:class]).to include("text-[#946700]")
    end
  end

  describe "unknown variant" do
    it "falls back to info styling rather than crashing" do
      result = render_inline(described_class.new(variant: :neon, label: "X")) do |c|
        c.with_body { "Body" }
      end

      root = result.at_css("div")
      expect(root[:class]).to include("bg-[#eef4ff]")
    end
  end
end
