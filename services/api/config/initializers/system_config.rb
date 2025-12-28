# frozen_string_literal: true

# System Configuration Initializer
#
# This initializer ensures SystemConfig singleton is loaded and available
# at application startup. It also provides a logger for configuration status.

Rails.application.config.after_initialize do
  # Skip if running migrations or rake tasks (except specific config tasks)
  unless defined?(Rails::Console) ||
         File.basename($PROGRAM_NAME) == 'rake' && !ARGV.any? { |arg| arg.start_with?('config:') } ||
         defined?(Rails::Server)
    next
  end

  begin
    # Ensure SystemConfig singleton exists
    config = SystemConfig.instance

    Rails.logger.info "✅ SystemConfig loaded: domain=#{config.domain}"

    # Warn if critical fields are missing
    warnings = []
    warnings << "DOMAIN not configured" if config.domain.blank?
    warnings << "AMS_CALLBACK_URL not configured" if config.ams_callback_url.blank?
    warnings << "POSTAL_API_KEY not configured" if config.postal_api_key.blank?

    if warnings.any?
      Rails.logger.warn "⚠️  SystemConfig warnings:"
      warnings.each { |w| Rails.logger.warn "   - #{w}" }
      Rails.logger.warn "   Configure via Dashboard Settings or run: rake config:load_from_env"
    end

  rescue ActiveRecord::StatementInvalid, PG::UndefinedTable => e
    # Database not ready yet (migrations haven't run)
    Rails.logger.info "ℹ️  SystemConfig skipped: database not ready (run migrations first)"
  rescue StandardError => e
    Rails.logger.error "❌ Failed to load SystemConfig: #{e.message}"
    Rails.logger.error e.backtrace.first(5).join("\n")
  end
end
