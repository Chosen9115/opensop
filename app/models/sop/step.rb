class Sop::Step < ApplicationRecord
  self.table_name = "sop_steps"

  STEP_TYPES = %w[form automated judgment approval webhook subprocess notification wait llm loop].freeze
  STATES = %w[pending active completed failed skipped].freeze
  SUB_STATES = %w[running waiting_for_input waiting_for_callback waiting_for_approval escalated waiting_for_worker].freeze

  belongs_to :instance,
             class_name: "Sop::Instance",
             foreign_key: :instance_id

  belongs_to :parent_iteration,
             class_name: "Sop::StepIteration",
             foreign_key: :parent_iteration_id,
             optional: true

  has_many :llm_calls,
           class_name: "Sop::LlmCall",
           foreign_key: :step_id,
           dependent: :destroy

  has_many :iterations,
           class_name: "Sop::StepIteration",
           foreign_key: :parent_step_id,
           dependent: :destroy,
           inverse_of: :parent_step

  enum :state, {
    pending: "pending",
    active: "active",
    completed: "completed",
    failed: "failed",
    skipped: "skipped"
  }

  validates :step_id, presence: true
  validates :step_name, presence: true
  validates :step_type, presence: true, inclusion: { in: STEP_TYPES }
  validates :state, presence: true, inclusion: { in: STATES }
  validates :position, presence: true
  validates :attempt, numericality: { greater_than_or_equal_to: 1, only_integer: true }

  scope :ordered, -> { order(:position) }
  scope :active, -> { where(state: "active") }
  scope :waiting, -> {
    where(sub_state: %w[waiting_for_input waiting_for_callback waiting_for_approval escalated waiting_for_worker])
  }
end
