# frozen_string_literal: true

class CreateAiSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_settings, id: false do |t|
      t.integer :id, primary_key: true, default: 1
      t.string :openrouter_api_key
      t.string :model_name, default: 'anthropic/claude-3.5-sonnet', null: false
      t.float :temperature, default: 0.7, null: false
      t.integer :max_tokens, default: 4000, null: false
      t.boolean :enabled, default: false, null: false
      t.integer :total_analyses, default: 0, null: false
      t.integer :total_tokens_used, default: 0, null: false
      t.datetime :last_analysis_at

      t.timestamps
    end

    # Ensure only one settings record exists
    execute <<-SQL
      CREATE UNIQUE INDEX idx_ai_settings_singleton ON ai_settings ((id));
    SQL
  end
end
