# frozen_string_literal: true

module Ui
  module ApiDocs
    # Callout renders a colored left-border block used for AUTH, PREREQ,
    # IMPORTANT notices throughout the API reference.
    #
    # Usage:
    #   <%= render Ui::ApiDocs::CalloutComponent.new(variant: :info, label: "AUTH") do |c| %>
    #     <% c.with_body do %>Requires X-SOP-Token. See Authentication.<% end %>
    #   <% end %>
    class CalloutComponent < ViewComponent::Base
      renders_one :body

      VARIANTS = {
        info: {
          bg:     "bg-[#eef4ff]",
          border: "border-l-[4px] border-[#1f4ed8]",
          label_color: "text-[#1f4ed8]"
        },
        warn: {
          bg:     "bg-[#fdf3d680]",
          border: "border-l-[4px] border-[#946700]",
          label_color: "text-[#946700]"
        }
      }.freeze

      attr_reader :variant, :label

      def initialize(variant: :info, label: nil)
        @variant = variant.to_sym
        @label   = label
      end

      def variant_classes
        v = VARIANTS.fetch(@variant, VARIANTS[:info])
        "#{v[:bg]} #{v[:border]}"
      end

      def label_color_class
        VARIANTS.fetch(@variant, VARIANTS[:info])[:label_color]
      end
    end
  end
end
