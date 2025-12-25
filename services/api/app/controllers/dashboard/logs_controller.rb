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
      @logs = @logs.page(params[:page]).per(50)

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
            log.message_id,
            log.campaign_id,
            log.recipient_masked,
            log.sender,
            log.subject,
            log.status,
            log.created_at.iso8601,
            log.sent_at&.iso8601,
            log.delivered_at&.iso8601
          ]
        end
      end

      send_data csv_data,
                filename: "email_logs_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv",
                type: 'text/csv'
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
