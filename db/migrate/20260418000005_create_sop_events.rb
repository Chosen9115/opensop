class CreateSopEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :sop_events, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :instance, type: :uuid, null: false,
                               foreign_key: { to_table: :sop_instances }
      t.string :step_id
      t.string :event_type, null: false
      t.string :actor
      t.jsonb :data, default: {}

      t.timestamps
    end

    add_index :sop_events, :event_type
    add_index :sop_events, :created_at
  end
end
