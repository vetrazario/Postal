# frozen_string_literal: true

module Api
  module V1
    class BounceStatusController < Api::V1::ApplicationController
      skip_before_action :authenticate_api_key

      # GET /api/v1/bounce_status/check?email=test@example.com&campaign_id=123
      def check
        email = params[:email]
        
        unless email.present?
          return render json: {
            error: 'Email parameter is required'
          }, status: :bad_request
        end

        campaign_id = params[:campaign_id]
        
        begin
          is_bounced = BouncedEmail.blocked?(email: email, campaign_id: campaign_id)
          is_unsubscribed = Unsubscribe.blocked?(email: email, campaign_id: campaign_id)
          
          render json: {
            email: mask_email(email),
            is_bounced: is_bounced,
            is_unsubscribed: is_unsubscribed,
            campaign_id: campaign_id,
            blocked: is_bounced || is_unsubscribed
          }
        rescue StandardError => e
          Rails.logger.error "BounceStatusController error: #{e.message}\n#{e.backtrace.join("\n")}"
          render json: {
            error: {
              code: 'internal_error',
              message: 'An internal error occurred'
            }
          }, status: :internal_server_error
        end
      end

      private

      def mask_email(email)
        return email if email.blank?
        
        local, domain = email.split('@', 2)
        return email if local.blank? || domain.blank?
        
        masked = local.length <= 2 ? "#{local[0]}***" : "#{local[0]}***#{local[-1]}"
        "#{masked}@#{domain}"
      end
    end
  end
end


