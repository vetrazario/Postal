class Api::V1::StatusController < Api::V1::ApplicationController
  def show
    email_log = EmailLog.find_by_external_message_id(params[:message_id])
    
    unless email_log
      return render json: {
        error: {
          code: "not_found",
          message: "Message not found"
        },
        request_id: @request_id
      }, status: :not_found
    end

    # Get events
    events = email_log.tracking_events.order(:created_at).map do |event|
      {
        type: event.event_type,
        timestamp: event.created_at.iso8601,
        ip: event.ip_address&.to_s,
        user_agent: event.user_agent
      }
    end

    render json: {
      message_id: email_log.external_message_id,
      local_id: email_log.message_id,
      status: email_log.status,
      recipient: email_log.recipient_masked,
      created_at: email_log.created_at.iso8601,
      sent_at: email_log.sent_at&.iso8601,
      delivered_at: email_log.delivered_at&.iso8601,
      events: events
    }, status: :ok
  end
end





