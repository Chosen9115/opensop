class CreatePasskeyCredentials < ActiveRecord::Migration[8.1]
  def change
    create_table :passkey_credentials, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :nickname, null: false, limit: 80
      t.string :transports, array: true, default: []
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :passkey_credentials, :external_id, unique: true
  end
end
