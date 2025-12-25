# frozen_string_literal: true

class AiAnalysis < ApplicationRecord
  # Validations
  validates :analysis_type, presence: true
  validates :status, presence: true, inclusion: { in: %w[processing completed failed] }

  # Scopes
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :processing, -> { where(status: 'processing') }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(analysis_type: type) }

  # Analysis types
  ANALYSIS_TYPES = {
    'bounce_analysis' => 'Bounce Reason Analysis',
    'time_optimization' => 'Send Time Optimization',
    'campaign_comparison' => 'Campaign Performance Comparison',
    'deliverability_insights' => 'Deliverability Insights'
  }.freeze

  # Mark as processing
  def mark_processing!
    update!(status: 'processing')
  end

  # Mark as completed
  def mark_completed!(analysis_result:, prompt_tokens:, completion_tokens:, total_tokens:, model_used:)
    update!(
      status: 'completed',
      analysis_result: analysis_result,
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: total_tokens,
      model_used: model_used
    )

    # Update AiSetting counters
    AiSetting.instance.increment_analysis!(total_tokens)
  end

  # Mark as failed
  def mark_failed!(error_message)
    update!(
      status: 'failed',
      analysis_result: { error: error_message }
    )
  end

  # Type display name
  def type_display_name
    ANALYSIS_TYPES[analysis_type] || analysis_type.titleize
  end

  # Result summary
  def result_summary
    return nil unless analysis_result.present?

    if analysis_result.is_a?(Hash) && analysis_result['summary']
      analysis_result['summary']
    elsif analysis_result.is_a?(String)
      analysis_result.truncate(200)
    else
      analysis_result.to_json.truncate(200)
    end
  end

  # Cost estimation
  def estimated_cost
    return 0 unless total_tokens.to_i.positive?

    ai_setting = AiSetting.instance
    (total_tokens.to_f / 1000 * ai_setting.estimated_cost_per_1k_tokens).round(4)
  end

  # Format result as markdown
  def formatted_result
    return 'No result available' unless analysis_result.present?

    if analysis_result.is_a?(Hash)
      JSON.pretty_generate(analysis_result)
    else
      analysis_result.to_s
    end
  end
end
