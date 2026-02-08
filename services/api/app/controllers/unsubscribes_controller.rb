class UnsubscribesController < ActionController::Base
  skip_before_action :verify_authenticity_token
  layout 'application'

  # GET /unsubscribe?eid=BASE64_EMAIL&cid=BASE64_CAMPAIGN_ID
  def show
    @email = decode_param(params[:eid])
    @campaign_id = decode_param(params[:cid])

    # Check if already unsubscribed
    @already_unsubscribed = Unsubscribe.exists?(email: @email, campaign_id: @campaign_id)
  end

  # POST /unsubscribe
  def create
    email = decode_param(params[:eid])
    campaign_id = decode_param(params[:cid])

    if email.present?
      Unsubscribe.record_unsubscribe(
        email: email,
        campaign_id: campaign_id,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        reason: params[:reason] || 'user_request'
      )

      # Create tracking event and notify AMS
      email_log = EmailLog.where(recipient: email, campaign_id: campaign_id)
                          .order(created_at: :desc).first

      if email_log
        TrackingEvent.create(
          email_log: email_log,
          event_type: 'unsubscribe',
          event_data: { campaign_id: campaign_id, reason: params[:reason] || 'user_request' },
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )

        ReportToAmsJob.perform_later(email_log.external_message_id, 'unsubscribed', nil, {
          campaign_id: campaign_id,
          reason: params[:reason] || 'user_request'
        })
      end

      # Update campaign stats
      if campaign_id.present?
        CampaignStats.find_or_initialize_for(campaign_id).increment_unsubscribed
      end

      Rails.logger.info "Unsubscribe: #{email} from campaign #{campaign_id}"

      redirect_to unsubscribe_page_path(eid: params[:eid], cid: params[:cid]), notice: 'Вы успешно отписались от рассылки.'
    else
      redirect_to root_path, alert: 'Неверная ссылка отписки.'
    end
  end

  private

  def decode_param(param)
    return nil if param.blank?
    Base64.urlsafe_decode64(param) rescue nil
  end
end
