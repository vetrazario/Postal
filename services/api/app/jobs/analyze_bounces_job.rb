# frozen_string_literal: true

class AnalyzeBouncesJob < ApplicationJob
  queue_as :default

  def perform(bounced_log_ids)
    analyzer = Ai::LogAnalyzer.new
    result = analyzer.analyze_bounces(bounced_log_ids)

    Rails.logger.info "Bounce analysis completed: #{result.inspect}"

    result
  rescue => e
    Rails.logger.error "Bounce analysis failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
