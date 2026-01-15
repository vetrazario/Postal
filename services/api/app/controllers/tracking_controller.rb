class TrackingController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_user!, if: :devise_controller?

  # Handle click tracking: GET /t/c/:token
  def click
    token = params[:token]
    click_record = EmailClick.find_by(token: token)

    if click_record
      # Update click info
      click_record.update!(
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        clicked_at: Time.current
      )

      # Update campaign stats
      update_campaign_stats(click_record.campaign_id, :clicks)

      # Log for debugging
      Rails.logger.info "Click tracked: #{click_record.id}, URL: #{click_record.url}"

      # Redirect to original URL
      redirect_to click_record.url, allow_other_host: true
    else
      # Token not found - redirect to homepage
      Rails.logger.warn "Invalid click token: #{token}"
      redirect_to root_url
    end
  end

  # Handle open tracking: GET /t/o/:token.gif
  def open
    token = params[:token]
    open_record = EmailOpen.find_by(token: token)

    if open_record
      # Update open info (only first open updates)
      if open_record.ip_address.blank?
        open_record.update!(
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          opened_at: Time.current
        )

        # Update campaign stats
        update_campaign_stats(open_record.campaign_id, :opens)

        Rails.logger.info "Open tracked: #{open_record.id}"
      end
    else
      Rails.logger.warn "Invalid open token: #{token}"
    end

    # Return 1x1 transparent GIF
    send_data(
      Base64.decode64('R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7'),
      type: 'image/gif',
      disposition: 'inline'
    )
  end

  private

  def update_campaign_stats(campaign_id, metric)
    return if campaign_id.blank? || campaign_id == 'unknown'

    stats = CampaignStats.find_or_initialize_for(campaign_id)
    case metric
    when :clicks
      stats.increment_clicked
    when :opens
      stats.increment_opened
    end
  rescue StandardError => e
    Rails.logger.error "Failed to update campaign stats: #{e.message}"
  end
end
