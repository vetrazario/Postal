# frozen_string_literal: true

class AiSetting < ApplicationRecord
  # Encryption for API key
  encrypts :api_key_encrypted, deterministic: false

  # Alias for convenience
  alias_attribute :api_key, :api_key_encrypted
  alias_attribute :openrouter_api_key, :api_key_encrypted
  alias_attribute :ai_model, :model

  # Validations
  validates :provider, presence: true
  validates :model, presence: true

  # Singleton pattern - only one settings record
  def self.instance
    first_or_create!(id: 1) do |settings|
      settings.provider = 'openrouter'
      settings.model = 'anthropic/claude-sonnet-4'
      settings.enabled = false
      settings.settings = {
        'temperature' => 0.7,
        'max_tokens' => 4000,
        'total_tokens_used' => 0,
        'total_estimated_cost' => 0.0
      }
    end
  end

  # Check if AI is configured
  def configured?
    api_key.present?
  end

  # Check if AI is ready to use
  def ready?
    configured? && enabled?
  end

  # Get setting value
  def get_setting(key, default = nil)
    settings&.dig(key.to_s) || default
  end

  # Set setting value
  def set_setting(key, value)
    self.settings ||= {}
    settings[key.to_s] = value
    save!
  end

  # JSONB settings accessors
  def temperature
    get_setting('temperature', 0.7)
  end

  def temperature=(value)
    set_setting('temperature', value.to_f)
  end

  def max_tokens
    get_setting('max_tokens', 4000)
  end

  def max_tokens=(value)
    set_setting('max_tokens', value.to_i)
  end

  def total_tokens_used
    get_setting('total_tokens_used', 0)
  end

  def total_tokens_used=(value)
    set_setting('total_tokens_used', value.to_i)
  end

  def total_estimated_cost
    get_setting('total_estimated_cost', 0.0)
  end

  def total_estimated_cost=(value)
    set_setting('total_estimated_cost', value.to_f)
  end

  # Increment tokens used
  def increment_tokens!(amount)
    current = total_tokens_used
    self.settings ||= {}
    settings['total_tokens_used'] = current + amount.to_i
    save!
  end

  # Model display name
  def model_display_name
    model
  end
end
