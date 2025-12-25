# frozen_string_literal: true

class CompareCampaignsJob < ApplicationJob
  queue_as :default

  def perform(campaign_ids)
    analyzer = AI::LogAnalyzer.new
    result = analyzer.compare_campaigns(campaign_ids)

    Rails.logger.info "Campaign comparison completed for campaigns #{campaign_ids.join(', ')}: #{result.inspect}"

    result
  rescue => e
    Rails.logger.error "Campaign comparison failed for campaigns #{campaign_ids.join(', ')}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise
  end
end
