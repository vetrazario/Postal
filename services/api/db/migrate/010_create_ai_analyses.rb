# frozen_string_literal: true

class CreateAiAnalyses < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_analyses do |t|
      t.string :analysis_type, null: false, comment: 'bounce_analysis, time_optimization, campaign_comparison'
      t.datetime :period_start
      t.datetime :period_end
      t.text :prompt
      t.text :result
      t.json :metadata
      t.integer :tokens_used, default: 0
      t.float :duration_seconds
      t.string :model_used
      t.string :status, default: 'completed', null: false, comment: 'processing, completed, failed'

      t.timestamps
    end

    add_index :ai_analyses, :analysis_type
    add_index :ai_analyses, :status
    add_index :ai_analyses, :created_at
    add_index :ai_analyses, [:analysis_type, :created_at]
  end
end
