class CreateSopSchedules < ActiveRecord::Migration[8.1]
  def change
    create_table :sop_schedules, id: :uuid, default: "gen_random_uuid()" do |t|
      t.string  :name, null: false
      t.text    :description
      t.string  :process_name, null: false
      t.string  :cron_expression, null: false
      t.jsonb   :inputs, default: {}, null: false
      t.string  :timezone, null: false, default: "UTC"
      t.boolean :enabled, null: false, default: true
      t.datetime :last_run_at
      t.datetime :next_run_at
      t.uuid    :last_instance_id
      t.string  :last_status
      t.integer :failure_count, null: false, default: 0
      t.timestamps
    end
    add_index :sop_schedules, [:enabled, :next_run_at]
    add_index :sop_schedules, :process_name
  end
end
