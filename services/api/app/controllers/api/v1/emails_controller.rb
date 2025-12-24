class Api::V1::EmailsController < Api::V1::ApplicationController
  include ApiResponse

  def send_email
    service = EmailSendingService.new(email_params)
    result = service.send_single

    if result.success?
      render_queued(result.email_log)
    else
      render_error('validation_error', result.error)
    end
  rescue StandardError => e
    Rails.logger.error "EmailsController error: #{e.message}"
    render_error('internal_error', 'Failed to queue email', status: :internal_server_error)
  end

  private

  def email_params
    params.permit(
      :recipient, :from_name, :from_email, :subject, :template_id,
      variables: {}, tracking: [:message_id, :campaign_id]
    ).to_h.deep_symbolize_keys
  end
end
