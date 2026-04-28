class AddToolsToSopSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :sop_steps, :tools, :jsonb, default: []
    add_index :sop_steps, :tools, using: :gin
  end
end
