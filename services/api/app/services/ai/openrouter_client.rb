# frozen_string_literal: true

require 'http'
require 'json'

module Ai
  class OpenrouterClient
    API_URL = 'https://openrouter.ai/api/v1/chat/completions'

    def initialize
      @settings = AiSetting.instance
    end

    def chat(messages:, max_tokens: nil)
      unless @settings.enabled?
        raise StandardError, 'AI analytics is not enabled'
      end

      unless @settings.openrouter_api_key.present?
        raise StandardError, 'OpenRouter API key is not configured'
      end

      response = HTTP.headers(
        'Authorization' => "Bearer #{@settings.openrouter_api_key}",
        'Content-Type' => 'application/json',
        'HTTP-Referer' => ENV.fetch('DOMAIN', 'https://linenarrow.com'),
        'X-Title' => 'Email Sender Analytics'
      ).post(API_URL, json: {
        model: @settings.ai_model,
        messages: messages,
        max_tokens: max_tokens || @settings.max_tokens,
        temperature: @settings.temperature
      })

      unless response.status.success?
        raise StandardError, "OpenRouter API error: #{response.status} - #{response.body}"
      end

      result = JSON.parse(response.body.to_s)

      # Update usage statistics
      if result['usage']
        @settings.increment!(:total_tokens_used, result['usage']['total_tokens'] || 0)
        @settings.increment!(:total_prompt_tokens, result['usage']['prompt_tokens'] || 0)
        @settings.increment!(:total_completion_tokens, result['usage']['completion_tokens'] || 0)
      end

      {
        content: result.dig('choices', 0, 'message', 'content'),
        prompt_tokens: result.dig('usage', 'prompt_tokens') || 0,
        completion_tokens: result.dig('usage', 'completion_tokens') || 0,
        total_tokens: result.dig('usage', 'total_tokens') || 0,
        model: result['model'] || @settings.ai_model
      }
    end

    def analyze(prompt:, context:)
      messages = [
        {
          role: 'system',
          content: 'You are an expert email deliverability analyst. Analyze email sending data and provide actionable insights.'
        },
        {
          role: 'user',
          content: "#{prompt}\n\nContext:\n#{context}"
        }
      ]

      chat(messages: messages)
    end
  end
end
