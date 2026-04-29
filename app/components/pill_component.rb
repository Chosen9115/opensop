class PillComponent < ViewComponent::Base
  # Renders a Paper Pro status pill: small mono badge with a leading colored dot.
  #
  # Usage:
  #   <%= render PillComponent.new(state: :running) %>
  #   <%= render PillComponent.new(state: :completed, label: "Done") %>
  def initialize(state:, label: nil)
    @state = state
    @label = label
  end

  attr_reader :label

  def state_key
    @state.to_s
  end

  def bg_class
    palette[:bg]
  end

  def text_class
    palette[:text]
  end

  def dot_class
    palette[:dot]
  end

  private

  def palette
    case state_key
    when "running", "active", "info", "busy"
      { bg: "bg-info-bg", text: "text-info", dot: "bg-info" }
    when "completed", "ok", "succeeded", "success"
      { bg: "bg-ok-bg", text: "text-ok", dot: "bg-ok" }
    when "failed", "err", "error"
      { bg: "bg-err-bg", text: "text-err", dot: "bg-err" }
    when "waiting", "warn", "warning", "paused", "escalated"
      { bg: "bg-warn-bg", text: "text-warn", dot: "bg-warn" }
    else
      # cancelled / pending / neutral / draft / idle / archived / fallback
      { bg: "bg-bg-pill", text: "text-neutral", dot: "bg-neutral" }
    end
  end
end
