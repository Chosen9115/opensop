class CreateSopCallbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :sop_callbacks, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :instance, type: :uuid, null: false,
                               foreign_key: { to_table: :sop_instances }
      t.string :step_id, null: false
      t.string :callback_path, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :response, default: {}
      t.datetime :expires_at

      t.timestamps
    end

    add_index :sop_callbacks, :callback_path, unique: true
    add_index :sop_callbacks, :status
    add_index :sop_callbacks, :expires_at
  end
end
