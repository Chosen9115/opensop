# frozen_string_literal: true

module Ui
  module ApiDocs
    # CodePanel renders a dark-themed code block used throughout the API reference.
    #
    # Usage (tabbed):
    #   <%= render Ui::ApiDocs::CodePanelComponent.new(tabs: [[:curl, "curl"], [:node, "node"]]) do |panel| %>
    #     <% panel.with_pane(key: :curl) do %>...code...<% end %>
    #     <% panel.with_pane(key: :node) do %>...code...<% end %>
    #   <% end %>
    #
    # Usage (single body with label):
    #   <%= render Ui::ApiDocs::CodePanelComponent.new(label: "RESPONSE BODY") do |panel| %>
    #     <% panel.with_body do %>...code...<% end %>
    #   <% end %>
    class CodePanelComponent < ViewComponent::Base
      renders_many :panes, lambda { |key:|
        PaneSlot.new(key: key)
      }
      renders_one :body

      attr_reader :label, :tabs, :status, :copyable

      def initialize(label: nil, tabs: nil, status: nil, copyable: true)
        @label    = label
        @tabs     = tabs   # e.g. [[:curl, "curl"], [:node, "node"]]
        @status   = status # e.g. { code: 200, label: "RESPONSE" }
        @copyable = copyable
      end

      # Helper: is this panel in tabs mode?
      def tabs_mode?
        tabs.present?
      end

      # Slot class for individual panes
      class PaneSlot < ViewComponent::Base
        attr_reader :key

        def initialize(key:)
          @key = key
        end

        def call
          content
        end
      end
    end
  end
end
