class Sop::StepIteration < ApplicationRecord
  self.table_name = "sop_step_iterations"

  STATES = %w[running completed failed].freeze

  belongs_to :parent_step,
             class_name: "Sop::Step",
             foreign_key: :parent_step_id

  has_many :body_steps,
           class_name: "Sop::Step",
           foreign_key: :parent_iteration_id,
           dependent: :destroy

  enum :state, {
    running: "running",
    completed: "completed",
    failed: "failed"
  }, prefix: true

  validates :parent_step_id, presence: true
  validates :index, presence: true
  validates :state, presence: true
  validates :started_at, presence: true

  scope :ordered, -> { order(:index) }
end
