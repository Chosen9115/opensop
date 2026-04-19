class CreateSopProcesses < ActiveRecord::Migration[8.1]
  def change
    create_table :sop_processes, id: :uuid, default: "gen_random_uuid()" do |t|
      t.string :name, null: false
      t.string :version, null: false
      t.text :description
      t.jsonb :definition, null: false, default: {}
      t.string :owner
      t.string :tags, array: true, default: []
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :sop_processes, [ :name, :version ], unique: true
    add_index :sop_processes, :status
    add_index :sop_processes, :tags, using: :gin
  end
end
