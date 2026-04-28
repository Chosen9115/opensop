class AddParentIterationIdToSopSteps < ActiveRecord::Migration[8.1]
  def change
    add_column :sop_steps, :parent_iteration_id, :uuid
    add_index :sop_steps, :parent_iteration_id
  end
end
