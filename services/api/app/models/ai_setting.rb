# frozen_string_literal: true

class AiSetting < ApplicationRecord
  # Encryption for API key
  encrypts :api_key_encrypted, deterministic: false

  # Alias for convenience
  alias_attribute :api_key, :api_key_encrypted

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
        temperature: 0.7,
        max_tokens: 4000
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

  # Model display name
  def model_display_name
    model
  end
end
