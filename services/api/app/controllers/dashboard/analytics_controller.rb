# frozen_string_literal: true

module Dashboard
  class AnalyticsController < BaseController
    def show
      @overview_stats = overview_statistics
      @campaign_stats = campaign_statistics
      @recent_activity = recent_activity_data
    end

    def hourly
      date = params[:date]&.to_date || Date.current
      start_time = date.beginning_of_day
      end_time = date.end_of_day

      hourly_data = (0..23).map do |hour|
        hour_start = start_time + hour.hours
        hour_end = hour_start + 1.hour

        logs = EmailLog.where(created_at: hour_start...hour_end)

        {
          hour: hour,
          label: hour_start.strftime('%H:%M'),
          sent: logs.where(status: 'sent').count,
          delivered: logs.where(status: 'delivered').count,
          bounced: logs.where(status: 'bounced').count,
          opened: TrackingEvent.where(
            email_log_id: logs.ids,
            event_type: 'open',
            created_at: hour_start...hour_end
          ).count,
          clicked: TrackingEvent.where(
            email_log_id: logs.ids,
            event_type: 'click',
            created_at: hour_start...hour_end
          ).count
        }
      end

      render json: hourly_data
    end

    def daily
      days = (params[:days] || 30).to_i
      start_date = days.days.ago.beginning_of_day
      end_date = Time.current.end_of_day

      daily_data = (0...days).map do |offset|
        day_start = start_date + offset.days
        day_end = day_start.end_of_day

        logs = EmailLog.where(created_at: day_start..day_end)

        {
          date: day_start.to_date.iso8601,
          label: day_start.strftime('%b %d'),
          sent: logs.where(status: 'sent').count,
          delivered: logs.where(status: 'delivered').count,
          bounced: logs.where(status: 'bounced').count,
          failed: logs.where(status: 'failed').count,
          opened: TrackingEvent.where(
            email_log_id: logs.ids,
            event_type: 'open'
          ).count,
          clicked: TrackingEvent.where(
            email_log_id: logs.ids,
            event_type: 'click'
          ).count
        }
      end

      render json: daily_data
    end

    def campaigns
      # Get unique campaign IDs with statistics
      campaign_stats = EmailLog.group(:campaign_id).select(
        :campaign_id,
        'COUNT(*) as total_sent',
        'SUM(CASE WHEN status = \'delivered\' THEN 1 ELSE 0 END) as delivered',
        'SUM(CASE WHEN status = \'bounced\' THEN 1 ELSE 0 END) as bounced',
        'SUM(CASE WHEN status = \'failed\' THEN 1 ELSE 0 END) as failed',
        'MIN(created_at) as first_sent',
        'MAX(created_at) as last_sent'
      ).order('total_sent DESC').limit(50)

      campaigns_data = campaign_stats.map do |stat|
        email_log_ids = EmailLog.where(campaign_id: stat.campaign_id).pluck(:id)

        opens = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'open').count
        clicks = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'click').count
        unique_opens = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'open')
                                     .select(:email_log_id).distinct.count

        {
          campaign_id: stat.campaign_id,
          total_sent: stat.total_sent,
          delivered: stat.delivered,
          bounced: stat.bounced,
          failed: stat.failed,
          opens: opens,
          clicks: clicks,
          unique_opens: unique_opens,
          open_rate: stat.delivered > 0 ? (unique_opens.to_f / stat.delivered * 100).round(2) : 0,
          click_rate: stat.delivered > 0 ? (clicks.to_f / stat.delivered * 100).round(2) : 0,
          first_sent: stat.first_sent,
          last_sent: stat.last_sent
        }
      end

      render json: campaigns_data
    end

    private

    def overview_statistics
      {
        total_sent: EmailLog.count,
        total_delivered: EmailLog.where(status: 'delivered').count,
        total_bounced: EmailLog.where(status: 'bounced').count,
        total_failed: EmailLog.where(status: 'failed').count,
        total_opens: TrackingEvent.where(event_type: 'open').count,
        total_clicks: TrackingEvent.where(event_type: 'click').count,
        unique_opens: TrackingEvent.where(event_type: 'open').select(:email_log_id).distinct.count,
        unique_recipients: EmailLog.select(:recipient_masked).distinct.count,
        total_campaigns: EmailLog.select(:campaign_id).distinct.count
      }
    end

    def campaign_statistics
      EmailLog.group(:campaign_id)
              .select(:campaign_id, 'COUNT(*) as count')
              .order('count DESC')
              .limit(10)
              .map { |stat| { campaign_id: stat.campaign_id, count: stat.count } }
    end

    def recent_activity_data
      EmailLog.order(created_at: :desc)
              .limit(20)
              .map do |log|
        {
          message_id: log.message_id,
          campaign_id: log.campaign_id,
          recipient_masked: log.recipient_masked,
          status: log.status,
          created_at: log.created_at.iso8601
        }
      end
    end
  end
end
