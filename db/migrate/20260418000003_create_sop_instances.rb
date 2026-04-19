class CreateSopInstances < ActiveRecord::Migration[8.1]
  def change
    create_table :sop_instances, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :process, type: :uuid, null: true,
                              foreign_key: { to_table: :sop_processes }
      t.string :process_name, null: false
      t.string :process_version, null: false
      t.string :state, null: false, default: "pending"
      t.jsonb :inputs, default: {}
      t.jsonb :outputs, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :sop_instances, :state
    add_index :sop_instances, [ :process_name, :state ]
    add_index :sop_instances, :started_at
  end
end
