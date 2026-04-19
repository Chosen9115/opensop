class Sop::Instance < ApplicationRecord
  self.table_name = "sop_instances"

  STATES = %w[pending running completed failed cancelled].freeze

  belongs_to :process,
             class_name: "Sop::Process",
             foreign_key: :process_id,
             optional: true

  has_many :steps,
           -> { order(:position) },
           class_name: "Sop::Step",
           foreign_key: :instance_id,
           dependent: :destroy

  has_many :events,
           class_name: "Sop::Event",
           foreign_key: :instance_id,
           dependent: :destroy

  has_many :callbacks,
           class_name: "Sop::Callback",
           foreign_key: :instance_id,
           dependent: :destroy

  enum :state, {
    pending: "pending",
    running: "running",
    completed: "completed",
    failed: "failed",
    cancelled: "cancelled"
  }

  validates :process_name, presence: true
  validates :process_version, presence: true
  validates :state, presence: true, inclusion: { in: STATES }

  scope :active, -> { where(state: %w[pending running]) }
  scope :terminal, -> { where(state: %w[completed failed cancelled]) }
end
