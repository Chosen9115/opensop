class CreateAuthEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :auth_events, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :user, type: :uuid, null: true,
                          foreign_key: { to_table: :users }
      t.string :kind, null: false
      t.inet :ip_address
      t.string :user_agent, limit: 255
      t.jsonb :metadata, default: {}, null: false
      t.datetime :created_at, null: false
    end

    add_index :auth_events, :kind
    add_index :auth_events, :created_at
    add_index :auth_events, [ :user_id, :created_at ]
  end
end
