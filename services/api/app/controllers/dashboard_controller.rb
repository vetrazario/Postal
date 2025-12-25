class DashboardController < ActionController::Base
  # Skip CSRF for now (dashboard is internal)
  skip_before_action :verify_authenticity_token
  
  # Explicitly use application layout
  layout 'application'
  
  # Basic HTTP authentication
  before_action :authenticate_dashboard

  def index
    @period = params[:period] || 'today'
    @date_from, @date_to = calculate_period(@period)
    
    # Calculate statistics
    @stats = calculate_stats(@date_from, @date_to)
    
    # Recent emails (last 50)
    @recent_emails = EmailLog
      .includes(:tracking_events)
      .order(created_at: :desc)
      .limit(50)
  end

  def logs
    @status = params[:status]
    @campaign_id = params[:campaign_id]
    @period = params[:period] || 'today'
    @page = params[:page] || 1
    
    @date_from, @date_to = calculate_period(@period)
    
    # Build query
    @logs = EmailLog
      .includes(:tracking_events)
      .where(created_at: @date_from..@date_to)
    
    @logs = @logs.where(status: @status) if @status.present?
    @logs = @logs.where(campaign_id: @campaign_id) if @campaign_id.present?
    
    # Order and paginate
    @logs = @logs.order(created_at: :desc)
    
    # Simple pagination (50 per page)
    per_page = 50
    @total_pages = (@logs.count.to_f / per_page).ceil
    @current_page = @page.to_i
    @logs = @logs.offset((@current_page - 1) * per_page).limit(per_page)
    
    # Get unique campaign IDs for filter
    @campaigns = EmailLog.where(created_at: @date_from..@date_to).distinct.pluck(:campaign_id).compact.sort
  end

  private

  def authenticate_dashboard
    # Skip authentication if credentials not configured
    return true unless ENV["DASHBOARD_USERNAME"].present? && ENV["DASHBOARD_PASSWORD"].present?
    
    authenticate_or_request_with_http_basic("Dashboard") do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, ENV["DASHBOARD_USERNAME"]) &&
        ActiveSupport::SecurityUtils.secure_compare(password, ENV["DASHBOARD_PASSWORD"])
    end
  end

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

  def calculate_stats(date_from, date_to)
    base_query = EmailLog.where(created_at: date_from..date_to)
    
    total_sent = base_query.count
    total_delivered = base_query.where(status: 'delivered').count
    total_bounced = base_query.where(status: 'bounced').count
    total_failed = base_query.where(status: 'failed').count
    total_complained = base_query.where(status: 'complained').count
    
    # Tracking events
    email_log_ids = base_query.pluck(:id)
    total_opened = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'open').count
    total_clicked = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'click').count
    
    # Calculate rates
    delivery_rate = total_sent > 0 ? (total_delivered.to_f / total_sent * 100).round(2) : 0.0
    bounce_rate = total_sent > 0 ? (total_bounced.to_f / total_sent * 100).round(2) : 0.0
    open_rate = total_delivered > 0 ? (total_opened.to_f / total_delivered * 100).round(2) : 0.0
    click_rate = total_delivered > 0 ? (total_clicked.to_f / total_delivered * 100).round(2) : 0.0
    complaint_rate = total_sent > 0 ? (total_complained.to_f / total_sent * 100).round(2) : 0.0
    
    {
      summary: {
        total_sent: total_sent,
        total_delivered: total_delivered,
        total_bounced: total_bounced,
        total_failed: total_failed,
        total_opened: total_opened,
        total_clicked: total_clicked,
        total_complained: total_complained
      },
      rates: {
        delivery_rate: delivery_rate,
        bounce_rate: bounce_rate,
        open_rate: open_rate,
        click_rate: click_rate,
        complaint_rate: complaint_rate
      }
    }
  end
end
