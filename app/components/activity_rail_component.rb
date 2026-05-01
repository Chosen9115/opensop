class ActivityRailComponent < ViewComponent::Base
  # Renders the 320px right-hand activity rail for the Paper Pro shell.
  # Three tabs (Feed / Agents / Up next) drive separate panels powered by
  # the same component initializer; tab switching is handled client-side
  # by the `activity-rail` Stimulus controller.
  #
  # Usage:
  #   <%= render ActivityRailComponent.new(
  #         events: @rail_events,
  #         llm_calls: @rail_llm_calls,
  #         up_next: @rail_up_next
  #       ) %>
  MAX_EVENTS = 12
  MAX_LLM_CALLS = 12
  MAX_UP_NEXT = 12

  TAB_KEYS = %w[feed agents up_next].freeze

  def initialize(events: nil, llm_calls: nil, up_next: nil)
    @events = (events || []).first(MAX_EVENTS)
    @llm_calls = (llm_calls || []).first(MAX_LLM_CALLS)
    @up_next = (up_next || []).first(MAX_UP_NEXT)
  end

  attr_reader :events, :llm_calls, :up_next

  def feed_empty?
    events.blank?
  end

  def agents_empty?
    llm_calls.blank?
  end

  def up_next_empty?
    up_next.blank?
  end

  # ── Feed (Sop::Event) ─────────────────────────────────────────────────

  def dot_class_for(event)
    type = event.event_type.to_s
    return "bg-ok" if type.end_with?(".completed")
    return "bg-err" if type.end_with?(".failed")
    return "bg-info" if type.end_with?(".started", ".cancelled")
    return "bg-warn" if type.start_with?("step.waiting_") || type.end_with?(".escalated")
    "bg-fg-faint"
  end

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

  def time_ago_for(time)
    helpers.time_ago_in_words(time)
  rescue StandardError
    ""
  end

  # ── Agents (Sop::LlmCall) ─────────────────────────────────────────────

  def llm_call_dot_class(call)
    case call.status.to_s
    when "succeeded" then "bg-ok"
    when "errored", "schema_failed" then "bg-err"
    when "requested" then "bg-info"
    else "bg-fg-faint"
    end
  end

  def llm_call_dot_pulse_class(call)
    call.status.to_s == "requested" ? "animate-pp-pulse" : ""
  end

  def llm_call_target_for(call)
    process_name = call.step&.instance&.process_name.presence || "—"
    step_id = call.step&.step_id.presence
    step_id.present? ? "#{process_name}/#{step_id}" : process_name
  end

  def llm_call_time_for(call)
    call.started_at || call.created_at
  end

  # ── Up next (mixed: schedules + waiting steps) ────────────────────────

  # Each up_next item is a hash:
  #   { kind: :schedule|:waiting_step, label:, target:, eta_at:, dot: }
  def up_next_dot_class(item)
    case item[:kind]
    when :schedule then "bg-info"
    when :waiting_step then "bg-warn"
    else "bg-fg-faint"
    end
  end

  def up_next_eta_for(item)
    return "" if item[:eta_at].blank?
    eta = item[:eta_at]
    if eta > Time.current
      "in #{helpers.distance_of_time_in_words(Time.current, eta)}"
    else
      "#{helpers.time_ago_in_words(eta)} ago"
    end
  rescue StandardError
    ""
  end
end
