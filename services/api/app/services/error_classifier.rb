# frozen_string_literal: true

class ErrorClassifier
  # DEPRECATED: Moved to config/bounce_patterns.yml
  # Edit patterns via Dashboard → Mailing Rules → Bounce Patterns
  # ERROR_PATTERNS = {...}.freeze
  # NON_BOUNCE_CATEGORIES = %w[...].freeze
  # STOP_MAILING_CATEGORIES = %w[...].freeze

  class << self
    def classify(payload)
      output = extract_text(payload, :output) || ''
      details = extract_text(payload, :details) || ''
      status = extract_text(payload, :status) || ''

      full_text = "#{status} #{output} #{details}".downcase

      category = find_category(full_text)
      smtp_code = extract_smtp_code(output)
      should_add_to_bounce = should_add_to_bounce?(category)
      should_stop_mailing = should_stop_mailing?(category)

      {
        category: category,
        bounce_type: 'hard',
        smtp_code: smtp_code,
        message: output.presence || details.presence || status,
        should_add_to_bounce: should_add_to_bounce,
        should_stop_mailing: should_stop_mailing
      }
    end

    # Reload configuration from YAML (called after uploading new config)
    def reload_config!
      @config = nil
    end

    private

    def extract_text(payload, key)
      payload.dig(key) || payload.dig(key.to_s) || payload[key] || payload[key.to_s]
    end

    def find_category(text)
      config['patterns'].each do |category, data|
        patterns = data['patterns'] || []
        return category.to_sym if patterns.any? { |pattern| text.include?(pattern.downcase) }
      end
      :unknown
    end

    def should_add_to_bounce?(category)
      non_bounce = config['non_bounce_categories'] || []
      !non_bounce.include?(category.to_s)
    end

    def should_stop_mailing?(category)
      stop_categories = config['stop_mailing_categories'] || []
      stop_categories.include?(category.to_s)
    end

    def config
      @config ||= load_config
    end

    def load_config
      config_path = Rails.root.join('config', 'bounce_patterns.yml')
      YAML.safe_load(File.read(config_path))
    rescue StandardError => e
      Rails.logger.error "Failed to load bounce patterns: #{e.message}"
      # Fallback to defaults if file not found
      default_config
    end

    def default_config
      {
        'patterns' => {},
        'non_bounce_categories' => [],
        'stop_mailing_categories' => []
      }
    end

    def extract_smtp_code(text)
      return nil if text.blank?

      # Ищем SMTP код в формате "550 5.1.1" или просто "550"
      match = text.match(/(\d{3})(?:\s+[\d.]+)?/)
      match ? match[1] : nil
    end
  end
end

