class Api::V1::BatchesController < Api::V1::ApplicationController
  include ApiResponse

  def create
    messages = params[:messages] || []
    service = EmailSendingService.new(batch_params)
    result = service.send_batch(messages.map(&:to_unsafe_h).map(&:deep_symbolize_keys))

    if result.success?
      data = result.email_log
      render_batch_result(data[:batch_id], data[:results])
    else
      render_error('validation_error', result.error)
    end
  rescue StandardError => e
    Rails.logger.error "BatchesController error: #{e.message}"
    render_error('internal_error', 'Failed to process batch', status: :internal_server_error)
  end

  private

  def batch_params
    params.permit(
      :from_name, :from_email, :subject, :template_id, :campaign_id
    ).to_h.deep_symbolize_keys
  end
end
