class KeyValueListComponent < ViewComponent::Base
  def initialize(items:, empty_label: nil)
    @items = items.is_a?(Hash) ? items : {}
    @empty_label = empty_label || I18n.t("opensop.common.none")
  end

  def empty?
    @items.empty?
  end

  def entries
    @items
  end

  def format_value(value)
    case value
    when nil then I18n.t("opensop.common.none")
    when true then I18n.t("opensop.common.yes")
    when false then I18n.t("opensop.common.no")
    when Hash, Array then value.to_json
    else value.to_s
    end
  end

  attr_reader :empty_label
end
