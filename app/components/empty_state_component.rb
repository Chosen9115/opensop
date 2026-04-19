class EmptyStateComponent < ViewComponent::Base
  def initialize(title:, description: nil, icon: :inbox)
    @title = title
    @description = description
    @icon = icon
  end

  attr_reader :title, :description, :icon
end
