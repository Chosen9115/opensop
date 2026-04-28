class Sop::LlmCall < ApplicationRecord
  self.table_name = "sop_llm_calls"

  STATUSES = %w[requested succeeded schema_failed errored].freeze

  belongs_to :step,
             class_name: "Sop::Step",
             foreign_key: :step_id

  has_one :instance, through: :step

  enum :status, {
    requested: "requested",
    succeeded: "succeeded",
    schema_failed: "schema_failed",
    errored: "errored"
  }, prefix: true

  validates :model, presence: true
  validates :prompt_hash, presence: true
  validates :started_at, presence: true
  validates :attempt, presence: true,
                      numericality: { greater_than_or_equal_to: 1, only_integer: true }

  scope :recent, -> { order(started_at: :desc) }
end
