# frozen_string_literal: true

module Dashboard
  class SmtpCredentialsController < BaseController
    before_action :set_smtp_credential, only: [:edit, :update, :destroy, :toggle_active, :test_connection, :regenerate_password]

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
      require 'socket'

      result = test_smtp_relay_reachable

      respond_to do |format|
        format.json { render json: result }
      end
    end

    # Regenerate password for existing credential
    def regenerate_password
      new_password = SecureRandom.alphanumeric(24)
      @smtp_credential.update!(password_hash: BCrypt::Password.create(new_password))

      respond_to do |format|
        format.html {
          @generated_password = new_password
          render :show_credentials
        }
        format.json {
          render json: {
            success: true,
            username: @smtp_credential.username,
            password: new_password,
            message: 'Password regenerated successfully'
          }
        }
      end
    rescue => e
      respond_to do |format|
        format.html { redirect_to dashboard_smtp_credentials_path, alert: "Error: #{e.message}" }
        format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
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
      config = SystemConfig.instance
      {
        smtp_host: config.domain || 'linenarrow.com',
        smtp_port: config.smtp_relay_port || 2587,
        smtp_security: config.smtp_relay_tls_enabled ? 'TLS/STARTTLS' : 'None',
        smtp_username: credential.username,
        smtp_password: password,
        instructions: 'Use these credentials in AMS Enterprise SMTP settings'
      }
    end

    def test_smtp_relay_reachable
      require 'socket'
      require 'timeout'

      smtp_host = 'smtp-relay'
      smtp_port = SystemConfig.get(:smtp_relay_port) || 2587

      begin
        Timeout.timeout(5) do
          socket = TCPSocket.new(smtp_host, smtp_port)

          # Read SMTP banner
          banner = socket.gets
          socket.close

          if banner&.start_with?('220')
            {
              success: true,
              message: "SMTP Relay is running",
              banner: banner.strip,
              host: smtp_host,
              port: smtp_port,
              tested_at: Time.current
            }
          else
            {
              success: false,
              error: "Unexpected SMTP response: #{banner&.strip}",
              tested_at: Time.current
            }
          end
        end
      rescue Timeout::Error
        {
          success: false,
          error: 'Connection timeout - SMTP Relay not responding',
          host: smtp_host,
          port: smtp_port,
          tested_at: Time.current
        }
      rescue Errno::ECONNREFUSED
        {
          success: false,
          error: 'Connection refused - SMTP Relay not running',
          host: smtp_host,
          port: smtp_port,
          tested_at: Time.current
        }
      rescue SocketError => e
        {
          success: false,
          error: "DNS error: #{e.message}",
          tested_at: Time.current
        }
      rescue StandardError => e
        {
          success: false,
          error: "#{e.class}: #{e.message}",
          tested_at: Time.current
        }
      end
    end
  end
end
