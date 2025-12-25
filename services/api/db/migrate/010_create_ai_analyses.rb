# frozen_string_literal: true

class CreateAiAnalyses < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_analyses do |t|
      t.string :analysis_type, null: false, comment: 'bounce_analysis, time_optimization, campaign_comparison'
      t.string :campaign_id, comment: 'Associated campaign ID if applicable'
      t.json :analysis_result, comment: 'JSON result from AI analysis'
      t.integer :prompt_tokens, default: 0, null: false
      t.integer :completion_tokens, default: 0, null: false
      t.integer :total_tokens, default: 0, null: false
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
