class CreateSopLlmCalls < ActiveRecord::Migration[8.1]
  def change
    create_table :sop_llm_calls, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :step, type: :uuid, null: false,
                          foreign_key: { to_table: :sop_steps }
      t.string :model, null: false
      t.string :prompt_hash, null: false
      t.integer :attempt, null: false, default: 1
      t.string :status, null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cost_cents
      t.jsonb :request_payload, default: {}
      t.jsonb :response_payload, default: {}
      t.text :error
      t.datetime :started_at, null: false
      t.datetime :finished_at

      t.timestamps
    end

    add_index :sop_llm_calls, [ :step_id, :attempt ], unique: true
    add_index :sop_llm_calls, :status
  end
end
