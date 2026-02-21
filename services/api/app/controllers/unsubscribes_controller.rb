class UnsubscribesController < ActionController::Base
  skip_before_action :verify_authenticity_token
  layout false

  # GET /unsubscribe?eid=BASE64_EMAIL&cid=BASE64_CAMPAIGN_ID
  def show
    @email = decode_param(params[:eid])
    @campaign_id = decode_param(params[:cid])

    # Check if already unsubscribed (campaign-specific or global)
    @already_unsubscribed = Unsubscribe.blocked?(email: @email, campaign_id: @campaign_id)
  end

  # POST /unsubscribe (supports RFC 8058 One-Click: body List-Unsubscribe=One-Click, eid/cid in query or body)
  def create
    email = decode_param(params[:eid])
    campaign_id = decode_param(params[:cid])
    one_click = params['List-Unsubscribe'].to_s == 'One-Click'

    if email.present?
      Unsubscribe.record_unsubscribe(
        email: email,
        campaign_id: campaign_id,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        reason: params[:reason] || 'user_request'
      )
      Unsubscribe.record_unsubscribe(
        email: email,
        campaign_id: nil,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        reason: params[:reason] || 'user_request'
      )

      push_unsubscribe_to_ams_buffer(email: email, campaign_id: campaign_id)

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

      if campaign_id.present?
        CampaignStats.find_or_initialize_for(campaign_id).increment_unsubscribed
      end

      Rails.logger.info "Unsubscribe: #{email} from campaign #{campaign_id}"

      if one_click
        head :ok
      else
        redirect_to unsubscribe_page_path(eid: params[:eid], cid: params[:cid]), notice: 'Вы успешно отписались от рассылки.'
      end
    else
      if one_click
        head :bad_request
      else
        redirect_to root_path, alert: 'Неверная ссылка отписки.'
      end
    end
  end

  private

  def push_unsubscribe_to_ams_buffer(email:, campaign_id: nil)
    redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'))
    key = campaign_id.present? ? "ams_open_clicks:#{campaign_id}" : 'ams_unsubscribes_global'
    payload = { email: email, url: 'Unsubscribe_Click:DC,AE{|;', campaign_id: campaign_id }.to_json
    redis.sadd(key, payload)
    redis.expire(key, 86400)
  rescue StandardError => e
    Rails.logger.error "AMS unsubscribe buffer push error: #{e.message}"
  ensure
    redis&.close
  end

  def decode_param(param)
    return nil if param.blank?
    Base64.urlsafe_decode64(param) rescue nil
  end
end
