# frozen_string_literal: true

module Dashboard
  class WebhooksController < BaseController
    before_action :set_webhook, only: [:show, :edit, :update, :destroy, :test, :retry_failed]

    def index
      @webhooks = WebhookEndpoint.order(created_at: :desc)
    end

    def logs
      page = (params[:page] || 1).to_i
      per_page = 50
      @logs = WebhookLog.includes(:webhook_endpoint)
                        .order(created_at: :desc)
                        .limit(per_page)
                        .offset((page - 1) * per_page)

      # Filter by webhook endpoint if specified
      if params[:webhook_id].present?
        @logs = @logs.where(webhook_endpoint_id: params[:webhook_id])
      end

      # Filter by success/failure
      if params[:status].present?
        @logs = @logs.where(success: params[:status] == 'success')
      end
    end

    def show
      @recent_logs = @webhook.webhook_logs.order(created_at: :desc).limit(20)
    end

    def new
      @webhook = WebhookEndpoint.new
    end

    def create
      @webhook = WebhookEndpoint.new(webhook_params)

      if @webhook.save
        redirect_to dashboard_webhooks_path, notice: 'Webhook endpoint created successfully'
      else
        render :new
      end
    end

    def edit
    end

    def update
      if @webhook.update(webhook_params)
        redirect_to dashboard_webhooks_path, notice: 'Webhook endpoint updated successfully'
      else
        render :edit
      end
    end

    def destroy
      @webhook.destroy
      redirect_to dashboard_webhooks_path, notice: 'Webhook endpoint deleted'
    end

    def test
      test_data = {
        message_id: 'test_' + SecureRandom.hex(12),
        recipient: 'test@example.com',
        status: 'delivered',
        timestamp: Time.current.iso8601
      }

      begin
        @webhook.send_webhook('test', test_data)
        redirect_to dashboard_webhook_path(@webhook), notice: 'Test webhook sent successfully'
      rescue => e
        redirect_to dashboard_webhook_path(@webhook), alert: "Test failed: #{e.message}"
      end
    end

    def retry_failed
      failed_logs = @webhook.webhook_logs.where(success: false).where('created_at > ?', 24.hours.ago)

      retried_count = 0
      failed_logs.each do |log|
        begin
          @webhook.send_webhook(log.event_type, log.payload)
          retried_count += 1
        rescue
          # Continue with next log
        end
      end

      redirect_to dashboard_webhook_path(@webhook),
                  notice: "Retried #{retried_count} failed webhooks"
    end

    private

    def set_webhook
      @webhook = WebhookEndpoint.find(params[:id])
    end

    def webhook_params
      params.require(:webhook_endpoint).permit(
        :url,
        :secret_key,
        :active,
        :retry_count,
        :timeout,
        events: []
      )
    end
  end
end
