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
    when Hash, Array then JSON.pretty_generate(value)
    else value.to_s
    end
  end

  def complex?(value)
    value.is_a?(Hash) || value.is_a?(Array)
  end

  def summary_label(value)
    if value.is_a?(Array)
      I18n.t("opensop.common.json_summary.array", count: value.size)
    else
      I18n.t("opensop.common.json_summary.object", count: value.size)
    end
  end

  attr_reader :empty_label
end
