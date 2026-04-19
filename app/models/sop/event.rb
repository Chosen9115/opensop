class Sop::Event < ApplicationRecord
  self.table_name = "sop_events"

  belongs_to :instance,
             class_name: "Sop::Instance",
             foreign_key: :instance_id

  validates :event_type, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
