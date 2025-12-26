# frozen_string_literal: true

class AiSetting < ApplicationRecord
  # Encryption for API key
  encrypts :openrouter_api_key

  # Validations
  validates :ai_model, presence: true
  validates :temperature, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 2 }
  validates :max_tokens, numericality: { greater_than: 0, less_than_or_equal_to: 100000 }

  # Available models
  AVAILABLE_MODELS = {
    'anthropic/claude-3.5-sonnet' => 'Claude 3.5 Sonnet (Recommended)',
    'anthropic/claude-3-opus' => 'Claude 3 Opus',
    'anthropic/claude-3-sonnet' => 'Claude 3 Sonnet',
    'openai/gpt-4-turbo' => 'GPT-4 Turbo',
    'openai/gpt-4' => 'GPT-4',
    'meta-llama/llama-3-70b-instruct' => 'Llama 3 70B',
    'google/gemini-pro-1.5' => 'Gemini Pro 1.5'
  }.freeze

  # Singleton pattern - only one settings record
  def self.instance
    first_or_create!(id: 1) do |settings|
      settings.ai_model = 'anthropic/claude-3.5-sonnet'
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

  # Model display name
  def model_display_name
    AVAILABLE_MODELS[ai_model] || ai_model
  end
end
