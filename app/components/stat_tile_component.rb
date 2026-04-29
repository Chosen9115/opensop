class StatTileComponent < ViewComponent::Base
  TONES = %i[default running waiting completed failed].freeze

  def initialize(label:, value:, tone: :default, hint: nil)
    @label = label
    @value = value
    @tone = TONES.include?(tone) ? tone : :default
    @hint = hint
  end

  attr_reader :label, :value, :hint, :tone

  def show_dot?
    @tone != :default
  end

  def tone_dot_class
    case @tone
    when :running then "bg-info"
    when :waiting then "bg-warn"
    when :completed then "bg-ok"
    when :failed then "bg-err"
    else "bg-neutral"
    end
  end
end
