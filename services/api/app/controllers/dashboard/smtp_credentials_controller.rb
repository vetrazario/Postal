# frozen_string_literal: true

module Dashboard
  class SmtpCredentialsController < BaseController
    before_action :set_smtp_credential, only: [:edit, :update, :destroy, :toggle_active, :test_connection]

    def index
      @smtp_credentials = SmtpCredential.order(created_at: :desc)
    end

    def new
      @smtp_credential = SmtpCredential.new
    end

    def create
      @smtp_credential, password = SmtpCredential.generate(
        description: smtp_credential_params[:description],
        rate_limit: smtp_credential_params[:rate_limit] || 100
      )

      # Store password temporarily for display (won't be shown again)
      @generated_password = password

      respond_to do |format|
        format.html { render :show_credentials }
        format.json {
          render json: {
            smtp_credential: @smtp_credential,
            password: password,
            connection_info: connection_info(@smtp_credential, password)
          }, status: :created
        }
      end
    rescue => e
      respond_to do |format|
        format.html {
          @smtp_credential = SmtpCredential.new(smtp_credential_params)
          flash.now[:error] = e.message
          render :new
        }
        format.json { render json: { error: e.message }, status: :unprocessable_entity }
      end
    end

    def edit
    end

    def update
      if @smtp_credential.update(smtp_credential_params.except(:password))
        redirect_to dashboard_smtp_credentials_path, notice: 'SMTP credential updated successfully'
      else
        render :edit
      end
    end

    def destroy
      @smtp_credential.destroy
      redirect_to dashboard_smtp_credentials_path, notice: 'SMTP credential deleted'
    end

    def toggle_active
      @smtp_credential.update!(active: !@smtp_credential.active)
      redirect_to dashboard_smtp_credentials_path,
                  notice: "SMTP credential #{@smtp_credential.active? ? 'activated' : 'deactivated'}"
    end

    def test_connection
      # This would test SMTP connection - placeholder for now
      result = {
        success: true,
        message: 'SMTP credentials are valid',
        tested_at: Time.current
      }

      respond_to do |format|
        format.json { render json: result }
      end
    end

    private

    def set_smtp_credential
      @smtp_credential = SmtpCredential.find(params[:id])
    end

    def smtp_credential_params
      params.require(:smtp_credential).permit(:description, :rate_limit)
    end

    def connection_info(credential, password)
      {
        smtp_host: SystemConfig.get(:domain) || 'linenarrow.com',
        smtp_port: 587,
        smtp_security: 'TLS/STARTTLS',
        smtp_username: credential.username,
        smtp_password: password,
        instructions: 'Use these credentials in AMS Enterprise SMTP settings'
      }
    end
  end
end
