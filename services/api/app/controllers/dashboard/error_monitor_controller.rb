# frozen_string_literal: true

module Dashboard
  class ErrorMonitorController < BaseController
    def index
      @campaign_id = params[:campaign_id]
      @category = params[:category]
      @hours = params[:hours]&.to_i || 24
      
      @errors = DeliveryError.all
      @errors = @errors.by_campaign(@campaign_id) if @campaign_id.present?
      @errors = @errors.by_category(@category) if @category.present?
      @errors = @errors.where('created_at > ?', @hours.hours.ago)
      @errors = @errors.includes(:email_log).order(created_at: :desc).limit(100)
      
      # Статистика по категориям
      @stats = DeliveryError.count_by_category(
        campaign_id: @campaign_id,
        category: @category,
        window_minutes: @hours * 60
      )
      
      # Список кампаний для фильтра
      @campaigns = DeliveryError.distinct.pluck(:campaign_id).compact.sort
    end

    def stats
      campaign_id = params[:campaign_id]
      hours = params[:hours]&.to_i || 24
      
      category = params[:category]
      stats = DeliveryError.count_by_category(
        campaign_id: campaign_id,
        category: category,
        window_minutes: hours * 60
      )
      
      total = stats.values.sum
      
      render json: {
        stats: stats,
        total: total,
        categories: DeliveryError::CATEGORIES.map do |cat|
          {
            name: cat,
            count: stats[cat] || 0,
            percentage: total > 0 ? ((stats[cat] || 0).to_f / total * 100).round(2) : 0
          }
        end
      }
    end
  end
end

