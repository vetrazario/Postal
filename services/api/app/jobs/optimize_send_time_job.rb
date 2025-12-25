# frozen_string_literal: true

class OptimizeSendTimeJob < ApplicationJob
  queue_as :default

  def perform(campaign_id)
    analyzer = AI::LogAnalyzer.new
    result = analyzer.optimize_send_time(campaign_id)

    Rails.logger.info "Send time optimization completed for campaign #{campaign_id}: #{result.inspect}"

    result
  rescue => e
    Rails.logger.error "Send time optimization failed for campaign #{campaign_id}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
