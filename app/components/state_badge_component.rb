class StateBadgeComponent < ViewComponent::Base
  # Renders a colored pill for instance/step/process states or step types.
  #
  # Usage:
  #   <%= render StateBadgeComponent.new(state: "running") %>
  #   <%= render StateBadgeComponent.new(state: step.state, sub_state: step.sub_state) %>
  #   <%= render StateBadgeComponent.new(state: "approval", kind: :step_type) %>
  def initialize(state:, sub_state: nil, kind: :state, size: :sm)
    @state = state.to_s
    @sub_state = sub_state.to_s.presence
    @kind = kind
    @size = size
  end

  def label
    case @kind
    when :step_type
      I18n.t("opensop.steps.type.#{@state}", default: @state.humanize)
    when :instance_state
      I18n.t("opensop.instance_state.#{@state}", default: @state.humanize)
    when :step_state
      if @sub_state.present? && @state == "active"
        I18n.t("opensop.steps.sub_state.#{@sub_state}", default: @sub_state.humanize)
      else
        I18n.t("opensop.steps.state.#{@state}", default: @state.humanize)
      end
    else
      I18n.t("opensop.instance_state.#{@state}",
             default: I18n.t("opensop.steps.state.#{@state}", default: @state.humanize))
    end
  end

  def classes
    base = "inline-flex items-center gap-1.5 rounded-full font-medium border"
    sizing = @size == :md ? "px-2.5 py-0.5 text-xs" : "px-2 py-0.5 text-[11px]"
    "#{base} #{sizing} #{tone_classes}"
  end

  def dot_classes
    "h-1.5 w-1.5 rounded-full #{dot_tone}"
  end

  def show_dot?
    @kind != :step_type
  end

  private

  def tone_key
    case @kind
    when :step_type then :neutral
    else
      effective = @sub_state.presence || @state
      case effective
      when "running" then :running
      when "completed" then :completed
      when "failed" then :failed
      when "cancelled" then :cancelled
      when "pending" then :pending
      when "skipped" then :skipped
      when "active" then :running
      when "waiting_for_input", "waiting_for_approval", "waiting_for_callback", "waiting_for_condition", "waiting_for_subprocess" then :waiting
      when "escalated" then :warning
      else :neutral
      end
    end
  end

  def tone_classes
    case tone_key
    when :running then "bg-indigo-50 border-indigo-200 text-indigo-700"
    when :completed then "bg-emerald-50 border-emerald-200 text-emerald-700"
    when :failed then "bg-rose-50 border-rose-200 text-rose-700"
    when :cancelled then "bg-slate-100 border-slate-200 text-slate-600"
    when :pending then "bg-slate-50 border-slate-200 text-slate-600"
    when :skipped then "bg-slate-50 border-slate-200 text-slate-500"
    when :waiting then "bg-amber-50 border-amber-200 text-amber-700"
    when :warning then "bg-amber-50 border-amber-300 text-amber-800"
    else "bg-slate-50 border-slate-200 text-slate-700"
    end
  end

  def dot_tone
    case tone_key
    when :running then "bg-indigo-500"
    when :completed then "bg-emerald-500"
    when :failed then "bg-rose-500"
    when :cancelled then "bg-slate-400"
    when :pending then "bg-slate-300"
    when :skipped then "bg-slate-300"
    when :waiting then "bg-amber-500"
    when :warning then "bg-amber-600"
    else "bg-slate-400"
    end
  end
end
