# frozen_string_literal: true

module AI
  class LogAnalyzer
    def initialize
      @client = OpenrouterClient.new
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
        Analyze these bounced emails and provide:
        1. Common patterns or reasons for bounces
        2. Specific recommendations to reduce bounce rate
        3. Any red flags in the data (e.g., spam-like subjects, problematic domains)
        4. Suggested next steps

        Return your analysis in JSON format with keys: summary, patterns, recommendations, red_flags, next_steps
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
        analysis_result: analysis_result
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
