class StateBadgeComponent < ViewComponent::Base
  # Renders a state pill by delegating to PillComponent.
  # API preserved for backward compatibility.
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

  def call
    render PillComponent.new(state: pp_state, label: pretty_label)
  end

  private

  def pp_state
    effective = @sub_state.presence || @state
    case effective
    when "running", "active", "started" then "running"
    when "completed", "succeeded", "ok" then "completed"
    when "failed", "error" then "failed"
    when "cancelled" then "neutral"
    when "pending" then "neutral"
    when "skipped", "draft" then "neutral"
    when "waiting_for_input", "waiting_for_callback",
         "waiting_for_approval", "waiting_for_condition",
         "waiting_for_subprocess", "escalated", "paused", "waiting" then "waiting"
    else "neutral"
    end
  end

  def pretty_label
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
end
