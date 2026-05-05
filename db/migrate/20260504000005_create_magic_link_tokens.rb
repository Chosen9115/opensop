class CreateMagicLinkTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :magic_link_tokens, id: :uuid, default: "gen_random_uuid()" do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :purpose, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at
      t.inet :requested_ip

      t.datetime :created_at, null: false
    end

    add_index :magic_link_tokens, :token_digest, unique: true
    add_index :magic_link_tokens, :expires_at
  end
end
