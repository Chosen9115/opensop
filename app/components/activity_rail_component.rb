class ActivityRailComponent < ViewComponent::Base
  # Renders the 320px right-hand activity rail for the Paper Pro shell.
  # Shows up to 12 recent Sop::Event records as compact feed rows. When the
  # event list is blank, shows a centered empty state.
  #
  # Usage:
  #   <%= render ActivityRailComponent.new(events: @rail_events) %>
  MAX_EVENTS = 12

  def initialize(events:)
    @events = (events || []).first(MAX_EVENTS)
  end

  attr_reader :events

  def empty?
    events.blank?
  end

  # Tailwind class for the leading dot, derived from the event_type.
  def dot_class_for(event)
    type = event.event_type.to_s
    return "bg-ok" if type.end_with?(".completed")
    return "bg-err" if type.end_with?(".failed")
    return "bg-info" if type.end_with?(".started", ".cancelled")
    return "bg-warn" if type.start_with?("step.waiting_") || type.end_with?(".escalated")
    "bg-fg-faint"
  end

  # Live indicator for in-flight states pulses; finished states sit static.
  def dot_pulse_class(event)
    type = event.event_type.to_s
    if type.end_with?(".started") || type.start_with?("step.waiting_")
      "animate-pp-pulse"
    else
      ""
    end
  end

  def actor_for(event)
    event.event_type.to_s.split(".", 2).first.presence || "system"
  end

  def verb_for(event)
    event.event_type.to_s.split(".", 2)[1].to_s.tr("_", " ").presence || "—"
  end

  def target_for(event)
    process_name = event.instance&.process_name.presence ||
                   I18n.t("opensop.activity.no_actor", default: "—")

    if event.event_type.to_s.start_with?("step.")
      step_id = event.data.is_a?(Hash) ? event.data["step_id"] || event.data[:step_id] : nil
      return "#{process_name}/#{step_id}" if step_id.present?
    end

    process_name
  end

  def time_ago_for(event)
    helpers.time_ago_in_words(event.created_at)
  rescue StandardError
    ""
  end
end
