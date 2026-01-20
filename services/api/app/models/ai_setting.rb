# frozen_string_literal: true

class AiSetting < ApplicationRecord
  # Encryption for API key
  encrypts :openrouter_api_key

  # Validations
  validates :ai_model, presence: true, format: { with: /\A[\w\-]+\/[\w\-\.:]+\z/, message: "must be in OpenRouter format (e.g., anthropic/claude-sonnet-4)" }
  validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }
  validates :max_tokens, numericality: { greater_than: 0, less_than_or_equal_to: 100000 }

  # Singleton pattern - only one settings record
  def self.instance
    first_or_create!(id: 1) do |settings|
      settings.ai_model = 'anthropic/claude-sonnet-4'
      settings.temperature = 0.7
      settings.max_tokens = 4000
      settings.enabled = false
    end
  end

  # Check if AI is configured
  def configured?
    openrouter_api_key.present?
  end

  # Check if AI is ready to use
  def ready?
    configured? && enabled?
  end

  # Increment analysis counters
  def increment_analysis!(tokens_used)
    increment!(:total_analyses)
    increment!(:total_tokens_used, tokens_used)
    update_column(:last_analysis_at, Time.current)
  end

  # Cost estimation (approximate)
  def estimated_cost_per_1k_tokens
    case ai_model
    when /claude-3.5-sonnet/
      0.003 # $0.003 per 1K tokens
    when /claude-3-opus/
      0.015 # $0.015 per 1K tokens
    when /gpt-4-turbo/
      0.01 # $0.01 per 1K tokens
    when /gpt-4/
      0.03 # $0.03 per 1K tokens
    else
      0.001 # Default estimate
    end
  end

  # Total estimated cost
  def total_estimated_cost
    (total_tokens_used / 1000.0 * estimated_cost_per_1k_tokens).round(2)
  end

  # Model display name (just return the model ID)
  def model_display_name
    ai_model
  end
end
