class Api::V1::StatsController < Api::V1::ApplicationController
  before_action :authenticate_api_key

  def index
    period = params[:period] || 'today'
    campaign_id = params[:campaign_id]

    date_from, date_to = calculate_period(period)

    # Base query with date filter
    base_query = EmailLog.where(created_at: date_from..date_to)
    base_query = base_query.where(campaign_id: campaign_id) if campaign_id.present?

    # Calculate statistics
    stats = calculate_stats(base_query, date_from, date_to)

    render json: {
      period: period,
      date_from: date_from.iso8601,
      date_to: date_to.iso8601,
      summary: stats[:summary],
      rates: stats[:rates],
      hourly: stats[:hourly]
    }
  end

  private

  def calculate_period(period)
    case period
    when 'today'
      [Date.current.beginning_of_day, Date.current.end_of_day]
    when 'yesterday'
      date = Date.current - 1.day
      [date.beginning_of_day, date.end_of_day]
    when 'week'
      [7.days.ago.beginning_of_day, Time.current]
    when 'month'
      [30.days.ago.beginning_of_day, Time.current]
    else
      [Date.current.beginning_of_day, Date.current.end_of_day]
    end
  end

  def calculate_stats(base_query, date_from, date_to)
    # Summary statistics
    total_sent = base_query.count
    total_delivered = base_query.where(status: 'delivered').count
    total_bounced = base_query.where(status: 'bounced').count
    total_failed = base_query.where(status: 'failed').count
    total_complained = base_query.where(status: 'complained').count

    # Tracking events for the period
    email_log_ids = base_query.pluck(:id)
    total_opened = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'open').count
    total_clicked = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'click').count

    # Calculate rates
    delivery_rate = total_sent > 0 ? (total_delivered.to_f / total_sent * 100).round(2) : 0.0
    bounce_rate = total_sent > 0 ? (total_bounced.to_f / total_sent * 100).round(2) : 0.0
    open_rate = total_delivered > 0 ? (total_opened.to_f / total_delivered * 100).round(2) : 0.0
    click_rate = total_delivered > 0 ? (total_clicked.to_f / total_delivered * 100).round(2) : 0.0
    complaint_rate = total_sent > 0 ? (total_complained.to_f / total_sent * 100).round(2) : 0.0

    # Hourly statistics
    hourly = calculate_hourly_stats(base_query, date_from, date_to)

    {
      summary: {
        total_sent: total_sent,
        delivered: total_delivered,
        bounced: total_bounced,
        failed: total_failed,
        opened: total_opened,
        clicked: total_clicked,
        complained: total_complained
      },
      rates: {
        delivery_rate: delivery_rate,
        bounce_rate: bounce_rate,
        open_rate: open_rate,
        click_rate: click_rate,
        complaint_rate: complaint_rate
      },
      hourly: hourly
    }
  end

  def calculate_hourly_stats(base_query, date_from, date_to)
    # Group by hour using SQL - PostgreSQL DATE_TRUNC returns timestamp
    start_date = date_from.beginning_of_day
    
    hourly_sent_raw = base_query
      .where(created_at: date_from..date_to)
      .group("DATE_TRUNC('hour', created_at)")
      .count

    hourly_delivered_raw = base_query
      .where(status: 'delivered', created_at: date_from..date_to)
      .group("DATE_TRUNC('hour', created_at)")
      .count

    # Build hash with hour as key for easier lookup
    hourly_sent = {}
    hourly_delivered = {}
    
    hourly_sent_raw.each do |timestamp, count|
      hour = timestamp.to_time.hour
      hourly_sent[hour] = count
    end
    
    hourly_delivered_raw.each do |timestamp, count|
      hour = timestamp.to_time.hour
      hourly_delivered[hour] = count
    end

    # Format for response - generate all 24 hours
    (0..23).map do |hour|
      {
        hour: hour,
        sent: hourly_sent[hour] || 0,
        delivered: hourly_delivered[hour] || 0
      }
    end
  end
end

