# frozen_string_literal: true

module Dashboard
  class AiAnalyticsController < BaseController
    def show
      @ai_settings = AiSetting.instance
      @recent_analyses = AiAnalysis.order(created_at: :desc).limit(10)
      @total_cost = @ai_settings.total_estimated_cost
    end

    def analyze_bounces
      ai_settings = AiSetting.instance

      unless ai_settings.enabled?
        return render json: { error: 'AI analytics is not enabled' }, status: :unprocessable_entity
      end

      # Get recent bounced emails
      bounced_logs = EmailLog.where(status: 'bounced')
                             .where('created_at > ?', 30.days.ago)
                             .limit(100)

      if bounced_logs.empty?
        return render json: { error: 'No bounced emails found in the last 30 days' }, status: :not_found
      end

      # Queue analysis job
      AnalyzeBouncesJob.perform_later(bounced_logs.pluck(:id))

      render json: {
        status: 'queued',
        message: 'Bounce analysis job queued',
        email_count: bounced_logs.count
      }, status: :accepted
    end

    def optimize_timing
      ai_settings = AiSetting.instance

      unless ai_settings.enabled?
        return render json: { error: 'AI analytics is not enabled' }, status: :unprocessable_entity
      end

      campaign_id = params[:campaign_id]

      unless campaign_id.present?
        return render json: { error: 'campaign_id is required' }, status: :bad_request
      end

      # Get campaign logs
      campaign_logs = EmailLog.where(campaign_id: campaign_id)

      if campaign_logs.empty?
        return render json: { error: 'Campaign not found' }, status: :not_found
      end

      # Queue analysis job
      OptimizeSendTimeJob.perform_later(campaign_id)

      render json: {
        status: 'queued',
        message: 'Send time optimization job queued',
        campaign_id: campaign_id
      }, status: :accepted
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

      # Queue analysis job
      CompareCampaignsJob.perform_later(campaign_ids)

      render json: {
        status: 'queued',
        message: 'Campaign comparison job queued',
        campaign_ids: campaign_ids
      }, status: :accepted
    end

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
  end
end
