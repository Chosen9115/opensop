# Declared with fully-qualified class name to avoid collision with the
# top-level Ruby `Process` module under Rails 8's Zeitwerk autoloader.
class Sop::Process < ApplicationRecord
  self.table_name = "sop_processes"

  STATUSES = %w[active deprecated archived].freeze

  has_many :instances,
           class_name: "Sop::Instance",
           foreign_key: :process_id,
           dependent: :restrict_with_error

  enum :status, {
    active: "active",
    deprecated: "deprecated",
    archived: "archived"
  }

  validates :name, presence: true
  validates :version, presence: true
  validates :name, uniqueness: { scope: :version }
  validates :status, inclusion: { in: STATUSES }

  scope :published, -> { where(status: "active") }
end
