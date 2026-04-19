class StatTileComponent < ViewComponent::Base
  TONES = %i[default running waiting completed failed].freeze

  def initialize(label:, value:, tone: :default, hint: nil)
    @label = label
    @value = value
    @tone = TONES.include?(tone) ? tone : :default
    @hint = hint
  end

  attr_reader :label, :value, :hint

  def top_border_class
    case @tone
    when :running then "border-t-indigo-500"
    when :waiting then "border-t-amber-500"
    when :completed then "border-t-emerald-500"
    when :failed then "border-t-rose-500"
    else "border-t-slate-300"
    end
  end

  def value_class
    case @tone
    when :running then "text-indigo-700"
    when :waiting then "text-amber-700"
    when :completed then "text-emerald-700"
    when :failed then "text-rose-700"
    else "text-slate-900"
    end
  end
end
