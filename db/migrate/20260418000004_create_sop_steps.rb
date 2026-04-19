class CreateSopSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :sop_steps, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :instance, type: :uuid, null: false,
                               foreign_key: { to_table: :sop_instances }
      t.string :step_id, null: false
      t.string :step_name, null: false
      t.string :step_type, null: false
      t.string :state, null: false, default: "pending"
      t.string :sub_state
      t.jsonb :inputs, default: {}
      t.jsonb :outputs, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error
      t.integer :attempt, null: false, default: 1
      t.string :decided_by
      t.float :confidence
      t.integer :position, null: false

      t.timestamps
    end

    add_index :sop_steps, [ :instance_id, :position ]
    add_index :sop_steps, [ :instance_id, :step_id ], unique: true
    add_index :sop_steps, :state
    add_index :sop_steps, :step_type
  end
end
