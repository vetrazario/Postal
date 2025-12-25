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
  def mark_completed!(result:, tokens_used:, model_used:, duration:)
    update!(
      status: 'completed',
      result: result,
      tokens_used: tokens_used,
      model_used: model_used,
      duration_seconds: duration
    )

    # Update AiSetting counters
    AiSetting.instance.increment_analysis!(tokens_used)
  end

  # Mark as failed
  def mark_failed!(error_message)
    update!(
      status: 'failed',
      metadata: (metadata || {}).merge(error: error_message)
    )
  end

  # Type display name
  def type_display_name
    ANALYSIS_TYPES[analysis_type] || analysis_type.titleize
  end

  # Period description
  def period_description
    return 'All time' unless period_start || period_end

    parts = []
    parts << "from #{period_start.strftime('%Y-%m-%d')}" if period_start
    parts << "to #{period_end.strftime('%Y-%m-%d')}" if period_end
    parts.join(' ')
  end

  # Result summary (first 200 chars)
  def result_summary
    return nil unless result.present?

    result.truncate(200)
  end

  # Cost estimation
  def estimated_cost
    return 0 unless tokens_used.to_i.positive?

    ai_setting = AiSetting.instance
    (tokens_used.to_f / 1000 * ai_setting.estimated_cost_per_1k_tokens).round(4)
  end

  # Format result as markdown
  def formatted_result
    return 'No result available' unless result.present?

    # Already in markdown format from OpenRouter
    result
  end

  # Duration in human-readable format
  def duration_human
    return 'N/A' unless duration_seconds

    if duration_seconds < 60
      "#{duration_seconds.round(1)}s"
    else
      minutes = (duration_seconds / 60).floor
      seconds = (duration_seconds % 60).round
      "#{minutes}m #{seconds}s"
    end
  end
end
