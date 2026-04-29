class TimestampComponent < ViewComponent::Base
  def initialize(time:, suffix: :ago, placeholder: nil)
    @time = time
    @suffix = suffix
    @placeholder = placeholder || I18n.t("opensop.common.never")
  end

  def present?
    @time.present?
  end

  def iso
    @time.iso8601
  end

  def relative
    words = helpers.time_ago_in_words(@time)
    case @suffix
    when :ago then "#{words} ago"
    when :in then "in #{words}"
    else words
    end
  end

  def absolute
    @time.strftime("%Y-%m-%d %H:%M UTC")
  end

  attr_reader :placeholder, :time
end
