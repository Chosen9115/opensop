class Sop::Callback < ApplicationRecord
  self.table_name = "sop_callbacks"

  STATUSES = %w[pending received expired].freeze

  belongs_to :instance,
             class_name: "Sop::Instance",
             foreign_key: :instance_id

  enum :status, {
    pending: "pending",
    received: "received",
    expired: "expired"
  }

  validates :step_id, presence: true
  validates :callback_path, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :generate_callback_path, on: :create

  private

  def generate_callback_path
    self.callback_path = "/sop/webhooks/#{SecureRandom.uuid}" if callback_path.blank?
  end
end
