class StepStateIconComponent < ViewComponent::Base
  def initialize(state:, sub_state: nil)
    @state = state.to_s
    @sub_state = sub_state.to_s.presence
  end

  def variant
    case @state
    when "completed" then :completed
    when "failed" then :failed
    when "skipped" then :skipped
    when "active"
      case @sub_state
      when "escalated" then :warning
      when "waiting_for_input", "waiting_for_approval", "waiting_for_callback", "waiting_for_condition", "waiting_for_subprocess" then :waiting
      else :running
      end
    else
      :pending
    end
  end

  def color_class
    case variant
    when :completed then "text-emerald-500"
    when :failed then "text-rose-500"
    when :skipped then "text-slate-400"
    when :waiting then "text-amber-500"
    when :warning then "text-amber-600"
    when :running then "text-indigo-500"
    else "text-slate-300"
    end
  end
end
