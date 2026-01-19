# frozen_string_literal: true

class AiAnalysis < ApplicationRecord
  # Associations
  belongs_to :email_log, optional: true

  # Validations
  validates :analysis_type, presence: true
  validates :provider, presence: true
  validates :model, presence: true
  validates :status, presence: true, inclusion: { in: %w[pending processing completed failed] }

  # Scopes
  scope :completed, -> { where(status: 'completed') }
  scope :failed, -> { where(status: 'failed') }
  scope :pending, -> { where(status: 'pending') }
  scope :processing, -> { where(status: 'processing') }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(analysis_type: type) }

  # Analysis types
  ANALYSIS_TYPES = {
    'bounce_analysis' => 'Bounce Reason Analysis',
    'time_optimization' => 'Send Time Optimization',
    'campaign_comparison' => 'Campaign Performance Comparison',
    'campaign_analysis' => 'Campaign Analysis',
    'deliverability_insights' => 'Deliverability Insights'
  }.freeze

  # Mark as processing
  def mark_processing!
    update!(status: 'processing')
  end

  # Mark as completed
  def mark_completed!(analysis_result)
    update!(
      status: 'completed',
      result: analysis_result.is_a?(String) ? analysis_result : analysis_result.to_json,
      analyzed_at: Time.current
    )
  end

  # Mark as failed
  def mark_failed!(error_message)
    update!(
      status: 'failed',
      result: { error: error_message }.to_json,
      analyzed_at: Time.current
    )
  end

  # Type display name
  def type_display_name
    ANALYSIS_TYPES[analysis_type] || analysis_type.titleize
  end

  # Parsed result
  def parsed_result
    return nil if result.blank?

    JSON.parse(result)
  rescue JSON::ParserError
    result
  end

  # Result summary
  def result_summary
    parsed = parsed_result
    return nil unless parsed

    if parsed.is_a?(Hash) && parsed['summary']
      parsed['summary']
    elsif parsed.is_a?(String)
      parsed.truncate(200)
    else
      parsed.to_json.truncate(200)
    end
  end

  # Format result as markdown
  def formatted_result
    return 'No result available' if result.blank?

    parsed = parsed_result
    if parsed.is_a?(Hash)
      JSON.pretty_generate(parsed)
    else
      parsed.to_s
    end
  end
end
