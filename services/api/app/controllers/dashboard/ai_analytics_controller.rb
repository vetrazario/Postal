# frozen_string_literal: true

module Dashboard
  class AiAnalyticsController < BaseController
    def show
      @ai_settings = AiSetting.instance
      @total_cost = @ai_settings.total_estimated_cost

      # Get campaigns for dropdown (unique campaign_ids with stats)
      @campaigns = EmailLog.where.not(campaign_id: [nil, ''])
                           .group(:campaign_id)
                           .select(
                             'campaign_id',
                             'COUNT(*) as total_sent',
                             'MIN(created_at) as started_at',
                             'MAX(created_at) as ended_at'
                           )
                           .order('MAX(created_at) DESC')
                           .limit(50)

      # Recent analyses
      @recent_analyses = AiAnalysis.order(created_at: :desc).limit(10)

      # If campaign selected, load its stats
      if params[:campaign_id].present?
        @selected_campaign = params[:campaign_id]
        @campaign_stats = load_campaign_stats(@selected_campaign)
      end

      # If analysis result exists in flash
      @analysis_result = flash[:analysis_result]
      @analysis_type = flash[:analysis_type]
    end

    def analyze_campaign
      ai_settings = AiSetting.instance

      unless ai_settings.enabled?
        flash[:alert] = 'AI аналитика отключена. Включите в настройках.'
        return redirect_to dashboard_ai_analytics_path
      end

      campaign_id = params[:campaign_id]

      unless campaign_id.present?
        flash[:alert] = 'Выберите кампанию'
        return redirect_to dashboard_ai_analytics_path
      end

      logs = EmailLog.where(campaign_id: campaign_id)

      if logs.empty?
        flash[:alert] = 'Кампания не найдена'
        return redirect_to dashboard_ai_analytics_path
      end

      begin
        analyzer = Ai::LogAnalyzer.new
        result = analyzer.analyze_campaign(campaign_id)

        flash[:analysis_result] = result
        flash[:analysis_type] = 'campaign'
      rescue => e
        Rails.logger.error "Campaign analysis failed: #{e.message}"
        flash[:alert] = "Ошибка анализа: #{e.message}"
      end

      redirect_to dashboard_ai_analytics_path(campaign_id: campaign_id)
    end

    def analyze_bounces
      ai_settings = AiSetting.instance

      unless ai_settings.enabled?
        flash[:alert] = 'AI аналитика отключена. Включите в настройках.'
        return redirect_to dashboard_ai_analytics_path
      end

      campaign_id = params[:campaign_id]

      # Get bounced emails - either for campaign or all recent
      bounced_logs = if campaign_id.present?
        EmailLog.where(campaign_id: campaign_id, status: 'bounced')
      else
        EmailLog.where(status: 'bounced').where('created_at > ?', 30.days.ago)
      end.limit(100)

      if bounced_logs.empty?
        flash[:alert] = 'Нет отказных писем для анализа'
        return redirect_to dashboard_ai_analytics_path(campaign_id: campaign_id)
      end

      begin
        analyzer = Ai::LogAnalyzer.new
        result = analyzer.analyze_bounces(bounced_logs.pluck(:id))

        flash[:analysis_result] = result
        flash[:analysis_type] = 'bounces'
      rescue => e
        Rails.logger.error "Bounce analysis failed: #{e.message}"
        flash[:alert] = "Ошибка анализа: #{e.message}"
      end

      redirect_to dashboard_ai_analytics_path(campaign_id: campaign_id)
    end

    # Legacy JSON endpoints for backwards compatibility
    def optimize_timing
      analyze_campaign
    end

    def compare_campaigns
      ai_settings = AiSetting.instance

      unless ai_settings.enabled?
        return render json: { error: 'AI analytics is not enabled' }, status: :unprocessable_entity
      end

      campaign_ids = params[:campaign_ids]

      unless campaign_ids.is_a?(Array) && campaign_ids.length >= 2
        return render json: { error: 'At least 2 campaign_ids are required' }, status: :bad_request
      end

      begin
        analyzer = Ai::LogAnalyzer.new
        result = analyzer.compare_campaigns(campaign_ids)
        render json: result
      rescue => e
        render json: { error: e.message }, status: :internal_server_error
      end
    end

    def history
      page = (params[:page] || 1).to_i
      per_page = 20
      @analyses = AiAnalysis.order(created_at: :desc)
                            .limit(per_page)
                            .offset((page - 1) * per_page)

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

    private

    def load_campaign_stats(campaign_id)
      logs = EmailLog.where(campaign_id: campaign_id)
      return nil if logs.empty?

      delivered = logs.where(status: 'delivered').count
      bounced = logs.where(status: 'bounced').count
      failed = logs.where(status: 'failed').count

      opens = TrackingEvent.where(email_log_id: logs.ids, event_type: 'open').count
      clicks = TrackingEvent.where(email_log_id: logs.ids, event_type: 'click').count

      # Hourly distribution
      hourly_opens = TrackingEvent.joins(:email_log)
                                  .where(email_logs: { campaign_id: campaign_id }, event_type: 'open')
                                  .group("EXTRACT(HOUR FROM tracking_events.created_at)")
                                  .count

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
        hourly_opens: hourly_opens,
        started_at: logs.minimum(:created_at),
        ended_at: logs.maximum(:created_at)
      }
    end
  end
end
