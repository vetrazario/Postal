# frozen_string_literal: true

module Dashboard
  class ApiKeysController < BaseController
    before_action :set_api_key, only: [:edit, :update, :destroy, :toggle_active]

    def index
      @api_keys = ApiKey.order(created_at: :desc)
    end

    def new
      @api_key = ApiKey.new
    end

    def create
      @api_key, raw_key = ApiKey.generate(
        name: api_key_params[:name],
        permissions: {
          send: api_key_params[:permissions]&.include?('send'),
          batch: api_key_params[:permissions]&.include?('batch')
        },
        rate_limit: api_key_params[:rate_limit] || 100,
        daily_limit: api_key_params[:daily_limit] || 0
      )

      # Store key temporarily for display (won't be shown again)
      @generated_key = raw_key

      respond_to do |format|
        format.html { render :show_key }
        format.json {
          render json: {
            api_key: @api_key,
            key: raw_key
          }, status: :created
        }
      end
    rescue StandardError => e
      respond_to do |format|
        format.html {
          @api_key = ApiKey.new(api_key_params)
          flash.now[:error] = e.message
          render :new
        }
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end

    def edit
    end

    def update
      if @api_key.update(api_key_params.except(:key))
        redirect_to dashboard_api_keys_path, notice: 'API key updated successfully'
      else
        render :edit
      end
    end

    def destroy
      @api_key.destroy
      redirect_to dashboard_api_keys_path, notice: 'API key deleted'
    end

    def toggle_active
      @api_key.update!(active: !@api_key.active)
      redirect_to dashboard_api_keys_path,
                  notice: "API key #{@api_key.active? ? 'activated' : 'deactivated'}"
    end

    private

    def set_api_key
      @api_key = ApiKey.find(params[:id])
    end

    def api_key_params
      params.require(:api_key).permit(:name, :rate_limit, :daily_limit, permissions: [])
    end
  end
end
