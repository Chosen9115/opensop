class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users, id: :uuid, default: "gen_random_uuid()" do |t|
      t.citext :email, null: false
      t.string :display_name, limit: 100
      t.string :role, null: false, default: "admin"
      t.datetime :last_signed_in_at

      t.timestamps
    end

    add_index :users, :email, unique: true
  end
end
