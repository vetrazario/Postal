# frozen_string_literal: true

require 'csv'

module Dashboard
  class LogsController < BaseController
    def index
      @logs = EmailLog.order(created_at: :desc)

      # Filter by status
      if params[:status].present? && EmailLog::STATUSES.include?(params[:status])
        @logs = @logs.where(status: params[:status])
      end

      # Search by recipient (masked)
      if params[:recipient].present?
        @logs = @logs.where('recipient_masked LIKE ?', "%#{params[:recipient]}%")
      end

      # Search by campaign ID
      if params[:campaign_id].present?
        @logs = @logs.where(campaign_id: params[:campaign_id])
      end

      # Date range filter
      if params[:date_from].present?
        @logs = @logs.where('created_at >= ?', params[:date_from])
      end

      if params[:date_to].present?
        @logs = @logs.where('created_at <= ?', params[:date_to])
      end

      # Pagination
      page = (params[:page] || 1).to_i
      per_page = 50
      @logs = @logs.limit(per_page).offset((page - 1) * per_page)

      # Stats for current filters
      @stats = calculate_filter_stats(@logs)
    end

    def show
      @log = EmailLog.find(params[:id])
      @tracking_events = @log.tracking_events.order(created_at: :asc)
    end

    def export
      @logs = EmailLog.order(created_at: :desc)

      # Apply same filters as index
      if params[:status].present? && EmailLog::STATUSES.include?(params[:status])
        @logs = @logs.where(status: params[:status])
      end

      if params[:recipient].present?
        @logs = @logs.where('recipient_masked LIKE ?', "%#{params[:recipient]}%")
      end

      if params[:campaign_id].present?
        @logs = @logs.where(campaign_id: params[:campaign_id])
      end

      if params[:date_from].present?
        @logs = @logs.where('created_at >= ?', params[:date_from])
      end

      if params[:date_to].present?
        @logs = @logs.where('created_at <= ?', params[:date_to])
      end

      # Limit export to 10,000 records
      @logs = @logs.limit(10_000)

      csv_data = CSV.generate(headers: true) do |csv|
        csv << [
          'Message ID',
          'Campaign ID',
          'Recipient',
          'Sender',
          'Subject',
          'Status',
          'Created At',
          'Sent At',
          'Delivered At'
        ]

        @logs.each do |log|
          csv << [
            log.message_id || '',
            log.campaign_id || '',
            log.recipient_masked || '',
            log.sender || '',
            log.subject || '',
            log.status || '',
            log.created_at&.iso8601 || '',
            log.sent_at&.iso8601 || '',
            log.delivered_at&.iso8601 || ''
          ]
        end
      end

      send_data csv_data,
                filename: "email_logs_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    rescue => e
      Rails.logger.error "Export logs error: #{e.message}\n#{e.backtrace.join("\n")}"
      head :internal_server_error
    end

    def export_unsubscribes
      # Проверка существования таблицы с обработкой ошибок
      table_exists = begin
        Unsubscribe.table_exists?
      rescue => e
        Rails.logger.warn "Could not check if unsubscribes table exists: #{e.message}"
        false
      end
      
      unless table_exists
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ['Email', 'Campaign ID', 'Reason', 'Unsubscribed At', 'IP Address', 'User Agent']
        end
        return send_data csv_data,
                        filename: "unsubscribes_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                        type: 'text/csv',
                        disposition: 'attachment'
      end
      
      unsubscribes = Unsubscribe.order(unsubscribed_at: :desc)
      
      # Фильтры
      unsubscribes = unsubscribes.where(campaign_id: params[:campaign_id]) if params[:campaign_id].present?
      unsubscribes = unsubscribes.where('unsubscribed_at >= ?', params[:date_from]) if params[:date_from].present?
      unsubscribes = unsubscribes.where('unsubscribed_at <= ?', params[:date_to]) if params[:date_to].present?
      
      # Лимит экспорта
      unsubscribes = unsubscribes.limit(10_000)
      
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'Campaign ID', 'Reason', 'Unsubscribed At', 'IP Address', 'User Agent']
        unsubscribes.each do |unsub|
          csv << [
            unsub.email || '',
            unsub.campaign_id || 'Global',
            unsub.reason || '',
            unsub.unsubscribed_at&.iso8601 || '',
            unsub.ip_address || '',
            unsub.user_agent || ''
          ]
        end
      end
      
      send_data csv_data,
                filename: "unsubscribes_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    rescue => e
      Rails.logger.error "Export unsubscribes error: #{e.message}\n#{e.backtrace.join("\n")}"
      # Возвращаем пустой CSV вместо ошибки
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'Campaign ID', 'Reason', 'Unsubscribed At', 'IP Address', 'User Agent']
      end
      send_data csv_data,
                filename: "unsubscribes_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    end

    def export_bounces
      # Проверка существования таблицы с обработкой ошибок
      table_exists = begin
        BouncedEmail.table_exists?
      rescue => e
        Rails.logger.warn "Could not check if bounced_emails table exists: #{e.message}"
        false
      end
      
      unless table_exists
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ['Email', 'Bounce Type', 'Category', 'SMTP Code', 'SMTP Message', 'Campaign ID', 'Bounce Count', 'First Bounced', 'Last Bounced']
        end
        return send_data csv_data,
                        filename: "bounces_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                        type: 'text/csv',
                        disposition: 'attachment'
      end
      
      bounces = BouncedEmail.order(last_bounced_at: :desc)
      
      # Фильтры
      bounces = bounces.where(campaign_id: params[:campaign_id]) if params[:campaign_id].present?
      bounces = bounces.where(bounce_type: params[:bounce_type]) if params[:bounce_type].present?
      bounces = bounces.where('last_bounced_at >= ?', params[:date_from]) if params[:date_from].present?
      bounces = bounces.where('last_bounced_at <= ?', params[:date_to]) if params[:date_to].present?
      
      # Лимит экспорта
      bounces = bounces.limit(10_000)
      
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'Bounce Type', 'Category', 'SMTP Code', 'SMTP Message', 'Campaign ID', 'Bounce Count', 'First Bounced', 'Last Bounced']
        bounces.each do |bounce|
          csv << [
            bounce.email || '',
            bounce.bounce_type || '',
            bounce.bounce_category || '',
            bounce.smtp_code || '',
            bounce.smtp_message || '',
            bounce.campaign_id || 'Global',
            bounce.bounce_count || 0,
            bounce.first_bounced_at&.iso8601 || '',
            bounce.last_bounced_at&.iso8601 || ''
          ]
        end
      end
      
      send_data csv_data,
                filename: "bounces_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    rescue => e
      Rails.logger.error "Export bounces error: #{e.message}\n#{e.backtrace.join("\n")}"
      # Возвращаем пустой CSV вместо ошибки
      csv_data = CSV.generate(headers: true) do |csv|
        csv << ['Email', 'Bounce Type', 'Category', 'SMTP Code', 'SMTP Message', 'Campaign ID', 'Bounce Count', 'First Bounced', 'Last Bounced']
      end
      send_data csv_data,
                filename: "bounces_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                type: 'text/csv',
                disposition: 'attachment'
    end

    private

    def calculate_filter_stats(logs_relation)
      # Use unscoped to get totals from filtered relation
      base = logs_relation.unscope(:limit, :offset)

      {
        total: base.count,
        queued: base.where(status: 'queued').count,
        processing: base.where(status: 'processing').count,
        sent: base.where(status: 'sent').count,
        delivered: base.where(status: 'delivered').count,
        bounced: base.where(status: 'bounced').count,
        failed: base.where(status: 'failed').count,
        complained: base.where(status: 'complained').count
      }
    end
  end
end
