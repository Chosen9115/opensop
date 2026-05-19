class CreateAuthSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :auth_sessions, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :user_agent, limit: 255
      t.inet :ip_address
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :auth_sessions, :token_digest, unique: true
    add_index :auth_sessions, :expires_at
  end
end
