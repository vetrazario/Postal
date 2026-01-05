# frozen_string_literal: true

module Ai
  class LogAnalyzer
    def initialize
      @client = OpenrouterClient.new
    end

    def analyze_campaign(campaign_id)
      logs = EmailLog.where(campaign_id: campaign_id)
      return { error: 'Campaign not found' } if logs.empty?

      # Collect comprehensive stats
      total = logs.count
      delivered = logs.where(status: 'delivered').count
      bounced = logs.where(status: 'bounced').count
      failed = logs.where(status: 'failed').count

      opens = TrackingEvent.where(email_log_id: logs.ids, event_type: 'open').count
      clicks = TrackingEvent.where(email_log_id: logs.ids, event_type: 'click').count

      # Hourly engagement
      hourly_stats = {}
      (0..23).each do |hour|
        hour_opens = TrackingEvent.joins(:email_log)
                                  .where(email_logs: { campaign_id: campaign_id }, event_type: 'open')
                                  .where('EXTRACT(HOUR FROM tracking_events.created_at) = ?', hour)
                                  .count
        hour_clicks = TrackingEvent.joins(:email_log)
                                   .where(email_logs: { campaign_id: campaign_id }, event_type: 'click')
                                   .where('EXTRACT(HOUR FROM tracking_events.created_at) = ?', hour)
                                   .count
        hourly_stats[hour] = { opens: hour_opens, clicks: hour_clicks } if hour_opens > 0 || hour_clicks > 0
      end

      # Domain distribution for bounces
      bounce_domains = logs.where(status: 'bounced').pluck(:recipient).map { |r| r.to_s.split('@').last }.tally.sort_by { |_, v| -v }.first(10).to_h

      prompt = <<~PROMPT
        Проанализируй эту email кампанию и дай рекомендации на русском языке:

        1. Общая оценка эффективности кампании
        2. Анализ времени открытий - когда лучше отправлять
        3. Проблемы с доставкой (если есть баунсы)
        4. Конкретные рекомендации по улучшению

        Ответь в JSON формате с ключами: summary, effectiveness_score (1-10), best_send_times, delivery_issues, recommendations
      PROMPT

      context = JSON.pretty_generate({
        campaign_id: campaign_id,
        period: "#{logs.minimum(:created_at)&.strftime('%Y-%m-%d %H:%M')} - #{logs.maximum(:created_at)&.strftime('%Y-%m-%d %H:%M')}",
        stats: {
          total_sent: total,
          delivered: delivered,
          bounced: bounced,
          failed: failed,
          opens: opens,
          clicks: clicks,
          delivery_rate: total > 0 ? (delivered.to_f / total * 100).round(1) : 0,
          open_rate: delivered > 0 ? (opens.to_f / delivered * 100).round(1) : 0,
          click_rate: delivered > 0 ? (clicks.to_f / delivered * 100).round(1) : 0,
          bounce_rate: total > 0 ? (bounced.to_f / total * 100).round(1) : 0
        },
        hourly_engagement: hourly_stats,
        bounce_domains: bounce_domains
      })

      result = @client.analyze(prompt: prompt, context: context)

      analysis_result = begin
        JSON.parse(result[:content])
      rescue JSON::ParserError
        { summary: result[:content], effectiveness_score: nil, best_send_times: [], delivery_issues: [], recommendations: [] }
      end

      AiAnalysis.create!(
        analysis_type: 'campaign_analysis',
        prompt_tokens: result[:prompt_tokens],
        completion_tokens: result[:completion_tokens],
        total_tokens: result[:total_tokens],
        model_used: result[:model],
        analysis_result: analysis_result,
        status: 'completed'
      )

      analysis_result
    end

    def analyze_bounces(bounced_log_ids)
      logs = EmailLog.where(id: bounced_log_ids, status: 'bounced')
                     .includes(:tracking_events)

      return { error: 'No bounced emails found' } if logs.empty?

      # Prepare context data
      bounce_data = logs.map do |log|
        {
          recipient_domain: log.recipient_masked.split('@').last,
          subject: log.subject,
          sent_at: log.sent_at&.iso8601,
          status_details: log.status_details
        }
      end

      prompt = <<~PROMPT
        Проанализируй эти отказные письма (bounces) и предоставь на русском языке:
        1. Общие паттерны и причины отказов
        2. Конкретные рекомендации по снижению bounce rate
        3. Красные флаги в данных (спамные темы, проблемные домены)
        4. Следующие шаги

        Ответь в JSON формате с ключами: summary, patterns, recommendations, red_flags, next_steps
      PROMPT

      context = JSON.pretty_generate({
        total_bounces: logs.count,
        date_range: "#{logs.minimum(:created_at)} to #{logs.maximum(:created_at)}",
        sample_bounces: bounce_data.take(20)
      })

      result = @client.analyze(prompt: prompt, context: context)

      # Parse the AI response (assuming JSON)
      analysis_result = begin
        JSON.parse(result[:content])
      rescue JSON::ParserError
        # If not valid JSON, structure it manually
        {
          summary: result[:content],
          patterns: [],
          recommendations: [],
          red_flags: [],
          next_steps: []
        }
      end

      # Save analysis
      AiAnalysis.create!(
        analysis_type: 'bounce_analysis',
        prompt_tokens: result[:prompt_tokens],
        completion_tokens: result[:completion_tokens],
        total_tokens: result[:total_tokens],
        model_used: result[:model],
        analysis_result: analysis_result,
        status: 'completed'
      )

      analysis_result
    end

    def optimize_send_time(campaign_id)
      logs = EmailLog.where(campaign_id: campaign_id)
                     .where.not(status: 'failed')

      return { error: 'Campaign not found or has no data' } if logs.empty?

      # Get hourly distribution of opens and clicks
      hourly_stats = {}

      (0..23).each do |hour|
        opens = TrackingEvent.joins(:email_log)
                            .where(email_logs: { campaign_id: campaign_id }, event_type: 'open')
                            .where('EXTRACT(HOUR FROM tracking_events.created_at) = ?', hour)
                            .count

        clicks = TrackingEvent.joins(:email_log)
                             .where(email_logs: { campaign_id: campaign_id }, event_type: 'click')
                             .where('EXTRACT(HOUR FROM tracking_events.created_at) = ?', hour)
                             .count

        hourly_stats[hour] = { opens: opens, clicks: clicks }
      end

      prompt = <<~PROMPT
        Analyze email engagement patterns by hour and recommend optimal send times.
        Consider:
        1. When do recipients open emails most?
        2. When do they click links most?
        3. What are the best and worst times to send?
        4. Any day-of-week patterns if available?

        Return JSON with: summary, best_hours, worst_hours, recommendations
      PROMPT

      context = JSON.pretty_generate({
        campaign_id: campaign_id,
        total_sent: logs.count,
        total_delivered: logs.where(status: 'delivered').count,
        hourly_engagement: hourly_stats
      })

      result = @client.analyze(prompt: prompt, context: context)

      analysis_result = begin
        JSON.parse(result[:content])
      rescue JSON::ParserError
        { summary: result[:content], best_hours: [], worst_hours: [], recommendations: [] }
      end

      AiAnalysis.create!(
        analysis_type: 'send_time_optimization',
        campaign_id: campaign_id,
        prompt_tokens: result[:prompt_tokens],
        completion_tokens: result[:completion_tokens],
        total_tokens: result[:total_tokens],
        model_used: result[:model],
        analysis_result: analysis_result
      )

      analysis_result
    end

    def compare_campaigns(campaign_ids)
      return { error: 'At least 2 campaigns required' } if campaign_ids.length < 2

      campaign_stats = campaign_ids.map do |cid|
        logs = EmailLog.where(campaign_id: cid)
        next nil if logs.empty?

        delivered = logs.where(status: 'delivered').count
        opens = TrackingEvent.where(email_log_id: logs.ids, event_type: 'open').count
        clicks = TrackingEvent.where(email_log_id: logs.ids, event_type: 'click').count
        bounces = logs.where(status: 'bounced').count

        {
          campaign_id: cid,
          total_sent: logs.count,
          delivered: delivered,
          opens: opens,
          clicks: clicks,
          bounces: bounces,
          open_rate: delivered > 0 ? (opens.to_f / delivered * 100).round(2) : 0,
          click_rate: delivered > 0 ? (clicks.to_f / delivered * 100).round(2) : 0,
          bounce_rate: logs.count > 0 ? (bounces.to_f / logs.count * 100).round(2) : 0
        }
      end.compact

      return { error: 'Not enough valid campaigns' } if campaign_stats.length < 2

      prompt = <<~PROMPT
        Compare these email campaigns and identify:
        1. Which campaign performed best and why?
        2. Key differences between campaigns
        3. Success factors to replicate
        4. Areas for improvement

        Return JSON with: summary, best_campaign, worst_campaign, success_factors, recommendations
      PROMPT

      context = JSON.pretty_generate({ campaigns: campaign_stats })

      result = @client.analyze(prompt: prompt, context: context)

      analysis_result = begin
        JSON.parse(result[:content])
      rescue JSON::ParserError
        { summary: result[:content], best_campaign: nil, worst_campaign: nil, success_factors: [], recommendations: [] }
      end

      AiAnalysis.create!(
        analysis_type: 'campaign_comparison',
        prompt_tokens: result[:prompt_tokens],
        completion_tokens: result[:completion_tokens],
        total_tokens: result[:total_tokens],
        model_used: result[:model],
        analysis_result: analysis_result
      )

      analysis_result
    end
  end
end
