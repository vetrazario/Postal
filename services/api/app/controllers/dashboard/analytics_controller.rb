# frozen_string_literal: true

module Dashboard
  class AnalyticsController < BaseController
    def show
      @ai_settings = AiSetting.instance
      @total_cost = @ai_settings.total_estimated_cost

      # Get campaigns for dropdown (unique campaign_ids with stats)
      @campaigns = EmailLog.where.not(campaign_id: [nil, '', 'unknown'])
                           .group(:campaign_id)
                           .select(
                             'campaign_id',
                             'COUNT(*) as total_sent',
                             'MIN(created_at) as started_at',
                             'MAX(created_at) as ended_at'
                           )
                           .order('MAX(created_at) DESC')
                           .limit(50)

      # Recent AI analyses
      @recent_analyses = AiAnalysis.order(created_at: :desc).limit(10)

      # If campaign selected, load its stats
      if params[:campaign_id].present?
        @selected_campaign = params[:campaign_id]
        @campaign_stats = load_campaign_stats(@selected_campaign)
      else
        # Overview stats for all campaigns
        @overview_stats = overview_statistics
        @campaign_stats = campaign_statistics
        @recent_activity = recent_activity_data
      end

      @selected_analysis = AiAnalysis.find_by(id: params[:analysis_id]) if params[:analysis_id]
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

    public

    # AI Analytics methods
    def analyze_bounces
      ai_settings = AiSetting.instance

      unless ai_settings.enabled?
        flash[:error] = 'AI analytics is not enabled'
        return redirect_to dashboard_analytics_path
      end

      # Get recent bounced emails
      bounced_logs = EmailLog.where(status: 'bounced')
                             .where('created_at > ?', 30.days.ago)
                             .limit(100)

      if bounced_logs.empty?
        flash[:error] = 'No bounced emails found in the last 30 days'
        return redirect_to dashboard_analytics_path
      end

      # Queue analysis job
      AnalyzeBouncesJob.perform_later(bounced_logs.pluck(:id))

      flash[:notice] = "Bounce analysis queued (#{bounced_logs.count} emails). Results will appear below shortly."
      redirect_to dashboard_analytics_path
    end

    def optimize_timing
      ai_settings = AiSetting.instance

      unless ai_settings.enabled?
        flash[:error] = 'AI analytics is not enabled'
        return redirect_to dashboard_analytics_path
      end

      campaign_id = params[:campaign_id]

      unless campaign_id.present?
        flash[:error] = 'Campaign ID is required'
        return redirect_to dashboard_analytics_path
      end

      # Get campaign logs
      campaign_logs = EmailLog.where(campaign_id: campaign_id)

      if campaign_logs.empty?
        flash[:error] = 'Campaign not found'
        return redirect_to dashboard_analytics_path
      end

      # Queue analysis job
      OptimizeSendTimeJob.perform_later(campaign_id)

      flash[:notice] = "Send time optimization queued for campaign #{campaign_id}. Results will appear below shortly."
      redirect_to dashboard_analytics_path(campaign_id: campaign_id)
    end

    def compare_campaigns
      ai_settings = AiSetting.instance

      unless ai_settings.enabled?
        flash[:error] = 'AI analytics is not enabled'
        return redirect_to dashboard_analytics_path
      end

      campaign_ids = params[:campaign_ids]&.reject(&:blank?)

      unless campaign_ids.is_a?(Array) && campaign_ids.length >= 2
        flash[:error] = 'At least 2 campaign IDs are required'
        return redirect_to dashboard_analytics_path
      end

      # Queue analysis job
      CompareCampaignsJob.perform_later(campaign_ids)

      flash[:notice] = "Campaign comparison queued for #{campaign_ids.length} campaigns. Results will appear below shortly."
      redirect_to dashboard_analytics_path
    end

    def analyze_campaign
      ai_settings = AiSetting.instance

      unless ai_settings.enabled?
        flash[:error] = 'AI analytics is not enabled'
        return redirect_to dashboard_analytics_path
      end

      campaign_id = params[:campaign_id]

      unless campaign_id.present?
        flash[:error] = 'Выберите кампанию'
        return redirect_to dashboard_analytics_path
      end

      logs = EmailLog.where(campaign_id: campaign_id)

      if logs.empty?
        flash[:error] = 'Кампания не найдена'
        return redirect_to dashboard_analytics_path
      end

      begin
        analyzer = Ai::LogAnalyzer.new
        # analyze_campaign уже создает запись в базе, возвращает только результат
        analysis_result = analyzer.analyze_campaign(campaign_id)

        # Найти созданную запись (последнюю для этой кампании)
        analysis = AiAnalysis.where(analysis_type: 'campaign_analysis')
                             .order(created_at: :desc)
                             .first

        if analysis
          flash[:notice] = "Анализ кампании завершен"
          redirect_to dashboard_analytics_path(campaign_id: campaign_id, analysis_id: analysis.id)
        else
          flash[:error] = "Ошибка: анализ не был сохранен"
          redirect_to dashboard_analytics_path(campaign_id: campaign_id)
        end
      rescue StandardError => e
        Rails.logger.error "Campaign analysis failed: #{e.message}"
        flash[:error] = "Ошибка анализа: #{e.message}"
        redirect_to dashboard_analytics_path(campaign_id: campaign_id)
      end
    end

    public

    def history
      page = (params[:page] || 1).to_i
      per_page = 20
      @analyses = AiAnalysis.order(created_at: :desc)
                            .limit(per_page)
                            .offset((page - 1) * per_page)

      # Filter by analysis type if specified
      if params[:analysis_type].present?
        @analyses = @analyses.where(analysis_type: params[:analysis_type])
      end

      render json: @analyses.map { |a|
        {
          id: a.id,
          analysis_type: a.analysis_type,
          prompt_tokens: a.prompt_tokens,
          completion_tokens: a.completion_tokens,
          total_tokens: a.total_tokens,
          model_used: a.model_used,
          analysis_result: a.analysis_result,
          created_at: a.created_at.iso8601
        }
      }
    end

    def export_opens
      require 'csv'
      
      campaign_id = params[:campaign_id]
      unless campaign_id.present?
        head :bad_request
        return
      end
      
      email_log_ids = EmailLog.where(campaign_id: campaign_id).pluck(:id)
      
      # Если нет email_logs для этой кампании, возвращаем пустой CSV
      if email_log_ids.empty?
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ['Email', 'Opened At', 'IP Address', 'User Agent']
        end
        return send_data csv_data,
                        filename: "campaign_#{campaign_id}_opens_#{Time.current.strftime('%Y%m%d')}.csv",
                        type: 'text/csv',
                        disposition: 'attachment'
      end
      
      opens = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'open')
                           .includes(:email_log)
                           .order(created_at: :desc)
                           .limit(10_000)
      
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'Opened At', 'IP Address', 'User Agent']
        opens.each do |open|
          next unless open.email_log # Защита от nil
          csv << [
            open.email_log.recipient_masked || '',
            open.created_at&.iso8601 || '',
            open.ip_address || '',
            open.user_agent || ''
          ]
        end
      end
      
      send_data csv_data,
                filename: "campaign_#{campaign_id}_opens_#{Time.current.strftime('%Y%m%d')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    rescue StandardError => e
      Rails.logger.error "Export opens error: #{e.message}\n#{e.backtrace.join("\n")}"
      head :internal_server_error
    end

    def export_clicks
      require 'csv'
      
      campaign_id = params[:campaign_id]
      unless campaign_id.present?
        head :bad_request
        return
      end
      
      email_log_ids = EmailLog.where(campaign_id: campaign_id).pluck(:id)
      
      if email_log_ids.empty?
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ['Email', 'URL', 'Clicked At', 'IP Address', 'User Agent']
        end
        return send_data csv_data,
                        filename: "campaign_#{campaign_id}_clicks_#{Time.current.strftime('%Y%m%d')}.csv",
                        type: 'text/csv',
                        disposition: 'attachment'
      end
      
      clicks = TrackingEvent.where(email_log_id: email_log_ids, event_type: 'click')
                            .includes(:email_log)
                            .order(created_at: :desc)
                            .limit(10_000)
      
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'URL', 'Clicked At', 'IP Address', 'User Agent']
        clicks.each do |click|
          next unless click.email_log # Защита от nil
          url = if click.event_data.is_a?(Hash)
                  click.event_data['url'] || click.event_data[:url] || 'N/A'
                elsif click.event_data.present?
                  begin
                    JSON.parse(click.event_data.to_s)['url'] || 'N/A'
                  rescue
                    'N/A'
                  end
                else
                  'N/A'
                end
          csv << [
            click.email_log.recipient_masked || '',
            url,
            click.created_at&.iso8601 || '',
            click.ip_address || '',
            click.user_agent || ''
          ]
        end
      end
      
      send_data csv_data,
                filename: "campaign_#{campaign_id}_clicks_#{Time.current.strftime('%Y%m%d')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    rescue StandardError => e
      Rails.logger.error "Export clicks error: #{e.message}\n#{e.backtrace.join("\n")}"
      head :internal_server_error
    end

    def export_unsubscribes
      require 'csv'
      
      campaign_id = params[:campaign_id]
      unless campaign_id.present?
        head :bad_request
        return
      end
      
      # Проверка существования таблицы с обработкой ошибок
      table_exists = begin
        Unsubscribe.table_exists?
      rescue StandardError => e
        Rails.logger.warn "Could not check if unsubscribes table exists: #{e.message}"
        false
      end
      
      unless table_exists
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ['Email', 'Unsubscribed At', 'IP Address', 'User Agent']
        end
        return send_data csv_data,
                        filename: "campaign_#{campaign_id}_unsubscribes_#{Time.current.strftime('%Y%m%d')}.csv",
                        type: 'text/csv',
                        disposition: 'attachment'
      end
      
      unsubscribes = Unsubscribe.where(campaign_id: campaign_id)
                                .order(unsubscribed_at: :desc)
                                .limit(10_000)
      
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'Unsubscribed At', 'IP Address', 'User Agent']
        unsubscribes.each do |unsub|
          csv << [
            unsub.email || '',
            unsub.unsubscribed_at&.iso8601 || '',
            unsub.ip_address || '',
            unsub.user_agent || ''
          ]
        end
      end
      
      send_data csv_data,
                filename: "campaign_#{campaign_id}_unsubscribes_#{Time.current.strftime('%Y%m%d')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    rescue StandardError => e
      Rails.logger.error "Export unsubscribes error: #{e.message}\n#{e.backtrace.join("\n")}"
      # Возвращаем пустой CSV вместо ошибки
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'Unsubscribed At', 'IP Address', 'User Agent']
      end
      send_data csv_data,
                filename: "campaign_#{campaign_id}_unsubscribes_#{Time.current.strftime('%Y%m%d')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    end

    def export_bounces
      require 'csv'
      
      campaign_id = params[:campaign_id]
      unless campaign_id.present?
        head :bad_request
        return
      end
      
      # Проверка существования таблицы с обработкой ошибок
      table_exists = begin
        BouncedEmail.table_exists?
      rescue StandardError => e
        Rails.logger.warn "Could not check if bounced_emails table exists: #{e.message}"
        false
      end
      
      unless table_exists
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ['Email', 'Bounce Type', 'Category', 'SMTP Code', 'SMTP Message', 'Bounced At']
        end
        return send_data csv_data,
                        filename: "campaign_#{campaign_id}_bounces_#{Time.current.strftime('%Y%m%d')}.csv",
                        type: 'text/csv',
                        disposition: 'attachment'
      end
      
      bounces = BouncedEmail.where(campaign_id: campaign_id)
                           .order(last_bounced_at: :desc)
                           .limit(10_000)
      
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'Bounce Type', 'Category', 'SMTP Code', 'SMTP Message', 'Bounced At']
        bounces.each do |bounce|
          csv << [
            bounce.email || '',
            bounce.bounce_type || '',
            bounce.bounce_category || '',
            bounce.smtp_code || '',
            bounce.smtp_message || '',
            bounce.last_bounced_at&.iso8601 || ''
          ]
        end
      end
      
      send_data csv_data,
                filename: "campaign_#{campaign_id}_bounces_#{Time.current.strftime('%Y%m%d')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    rescue StandardError => e
      Rails.logger.error "Export bounces error: #{e.message}\n#{e.backtrace.join("\n")}"
      # Возвращаем пустой CSV вместо ошибки
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'Bounce Type', 'Category', 'SMTP Code', 'SMTP Message', 'Bounced At']
      end
      send_data csv_data,
                filename: "campaign_#{campaign_id}_bounces_#{Time.current.strftime('%Y%m%d')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    end

    def load_campaign_stats(campaign_id)
      logs = EmailLog.where(campaign_id: campaign_id)
      return nil if logs.empty?

      delivered = logs.where(status: 'delivered').count
      bounced = logs.where(status: 'bounced').count
      failed = logs.where(status: 'failed').count

      opens = TrackingEvent.where(email_log_id: logs.ids, event_type: 'open').count
      clicks = TrackingEvent.where(email_log_id: logs.ids, event_type: 'click').count

      {
        total_sent: logs.count,
        delivered: delivered,
        bounced: bounced,
        failed: failed,
        opens: opens,
        clicks: clicks,
        delivery_rate: logs.count > 0 ? (delivered.to_f / logs.count * 100).round(1) : 0,
        bounce_rate: logs.count > 0 ? (bounced.to_f / logs.count * 100).round(1) : 0,
        open_rate: delivered > 0 ? (opens.to_f / delivered * 100).round(1) : 0,
        click_rate: delivered > 0 ? (clicks.to_f / delivered * 100).round(1) : 0,
        started_at: logs.minimum(:created_at),
        ended_at: logs.maximum(:created_at)
      }
    end
  end
end
