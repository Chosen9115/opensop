require "fugit"

class Sop::Schedule < ApplicationRecord
  self.table_name = "sop_schedules"

  LAST_STATUSES = %w[success failed].freeze

  validates :name, presence: true
  validates :process_name, presence: true
  validates :cron_expression, presence: true
  validates :last_status, inclusion: { in: LAST_STATUSES }, allow_nil: true
  validate :cron_expression_must_be_parseable
  validate :timezone_must_be_valid

  before_validation :set_next_run_at_if_blank

  scope :enabled, -> { where(enabled: true) }
  scope :due, -> { enabled.where("next_run_at IS NOT NULL AND next_run_at <= ?", Time.current) }

  def compute_next_run_at(from: Time.current)
    parsed = Fugit.parse_cron(cron_expression)
    return nil if parsed.nil?

    parsed.next_time(from.in_time_zone(timezone || "UTC"))&.to_t&.utc
  rescue ArgumentError, TZInfo::InvalidTimezoneIdentifier
    nil
  end

  def humanized_cron
    cron_expression
  end

  def due?
    enabled? && next_run_at.present? && next_run_at <= Time.current
  end

  private

  def cron_expression_must_be_parseable
    return if cron_expression.blank?

    parsed = begin
      Fugit.parse_cron(cron_expression)
    rescue StandardError
      nil
    end

    errors.add(:cron_expression, "is not a valid cron expression") if parsed.nil?
  end

  def timezone_must_be_valid
    return if timezone.blank?

    errors.add(:timezone, "is not a valid timezone") if ActiveSupport::TimeZone[timezone].blank?
  end

  def set_next_run_at_if_blank
    return if next_run_at.present?
    return if cron_expression.blank?

    self.next_run_at = compute_next_run_at
  end
end
