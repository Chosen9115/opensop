class CreateSopStepIterations < ActiveRecord::Migration[8.1]
  def change
    create_table :sop_step_iterations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :parent_step, type: :uuid, null: false,
                                 foreign_key: { to_table: :sop_steps }
      t.integer :index, null: false
      t.string :state, null: false, default: "running"
      t.jsonb :outputs, default: {}
      t.jsonb :iteration_inputs, default: {}
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.text :error

      t.timestamps
    end

    add_index :sop_step_iterations, [ :parent_step_id, :index ], unique: true
  end
end
