class UnsubscribesController < ActionController::Base
  include Rails.application.routes.url_helpers
  skip_before_action :verify_authenticity_token
  layout 'unsubscribes'

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
      Unsubscribe.find_or_create_by!(email: email, campaign_id: campaign_id) do |unsub|
        unsub.unsubscribed_at = Time.current
        unsub.reason = params[:reason] || 'User requested'
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
