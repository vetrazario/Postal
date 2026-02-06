# Сервис для создания и отправки email
# Единая точка входа для отправки писем
class EmailSendingService
  Result = Struct.new(:success?, :email_log, :error, keyword_init: true)

  def initialize(params)
    @params = params
  end

  # Отправка одного письма
  def send_single
    validation = validate_email(@params[:recipient], @params[:from_email])
    return Result.new(success?: false, error: validation[:error]) unless validation[:valid]

    email_log = create_email_log(
      recipient: @params[:recipient],
      external_message_id: @params.dig(:tracking, :message_id),
      campaign_id: @params.dig(:tracking, :campaign_id),
      variables: @params[:variables]
    )

    BuildEmailJob.perform_later(email_log.id)
    Result.new(success?: true, email_log: email_log)
  rescue ActiveRecord::RecordInvalid => e
    Result.new(success?: false, error: e.message)
  end

  # Отправка batch
  def send_batch(messages)
    return Result.new(success?: false, error: 'Batch must contain 1-100 messages') if messages.empty? || messages.size > 100

    validation = validate_email(@params[:from_email], @params[:from_email])
    return Result.new(success?: false, error: validation[:error]) unless validation[:valid]

    batch_id = SecureRandom.hex(12)
    results = process_batch_messages(messages, batch_id)

    Result.new(success?: true, email_log: { batch_id: batch_id, results: results })
  end

  private

  def validate_email(recipient, from_email)
    EmailValidator.validate(recipient: recipient, from_email: from_email)
  end

  def create_email_log(recipient:, external_message_id:, campaign_id:, variables:)
    message_id = MessageIdGenerator.generate.delete('<>')
    
    email_log = EmailLog.create!(
      message_id: message_id,
      external_message_id: external_message_id || SecureRandom.hex(12),
      campaign_id: campaign_id || 'unknown',
      recipient: recipient,
      sender: build_sender,
      subject: @params[:subject] || 'No Subject',
      status: 'queued',
      status_details: build_status_details(variables)
    )

    attach_template(email_log)
    email_log
  end

  def build_sender
    "#{@params[:from_name]} <#{@params[:from_email]}>"
  end

  def build_status_details(variables)
    {
      template_id: @params[:template_id],
      variables: variables || {},
      from_name: @params[:from_name],
      from_email: @params[:from_email]
    }
  end

  def attach_template(email_log)
    template = EmailTemplate.find_by_external_id(@params[:template_id])
    email_log.update!(template: template) if template
  end

  def process_batch_messages(messages, batch_id)
    results = { queued: [], failed: [] }

    messages.each do |msg|
      result = process_single_message(msg, batch_id)
      if result[:success]
        results[:queued] << result[:data]
      else
        results[:failed] << result[:data]
      end
    end

    results
  end

  def process_single_message(msg, batch_id)
    validation = validate_email(msg[:recipient], @params[:from_email])

    unless validation[:valid]
      track_validation_failure(msg, batch_id, validation[:error])
      return {
        success: false,
        data: { recipient: msg[:recipient], message_id: msg[:message_id], error: validation[:error] }
      }
    end

    email_log = create_batch_email_log(msg, batch_id)
    BuildEmailJob.perform_later(email_log.id)

    {
      success: true,
      data: { recipient: msg[:recipient], message_id: msg[:message_id], local_id: email_log.message_id }
    }
  rescue StandardError => e
    Rails.logger.error "Batch message error: #{e.message}"
    { success: false, data: { recipient: msg[:recipient], message_id: msg[:message_id], error: 'Internal error' } }
  end

  def track_validation_failure(msg, batch_id, error)
    campaign_id = @params[:campaign_id] || 'unknown'
    return if campaign_id == 'unknown'

    # Create EmailLog with failed status to track the validation failure
    email_log = EmailLog.create!(
      message_id: MessageIdGenerator.generate.delete('<>'),
      external_message_id: msg[:message_id] || SecureRandom.hex(12),
      campaign_id: campaign_id,
      recipient: msg[:recipient].presence || 'invalid@unknown',
      sender: build_sender,
      subject: @params[:subject] || 'No Subject',
      status: 'failed',
      status_details: { reason: 'validation_failed', error: error, batch_id: batch_id }
    )

    DeliveryError.create!(
      email_log: email_log,
      campaign_id: campaign_id,
      category: 'user_not_found',
      smtp_message: "Validation failed: #{error}"
    )

    CampaignStats.find_or_initialize_for(campaign_id).increment_failed
    CheckMailingThresholdsJob.perform_later(campaign_id)
  rescue StandardError => e
    Rails.logger.error "Failed to track validation failure: #{e.message}"
  end

  def create_batch_email_log(msg, batch_id)
    message_id = MessageIdGenerator.generate.delete('<>')
    
    email_log = EmailLog.create!(
      message_id: message_id,
      external_message_id: msg[:message_id] || SecureRandom.hex(12),
      campaign_id: @params[:campaign_id] || 'unknown',
      recipient: msg[:recipient],
      sender: build_sender,
      subject: @params[:subject] || 'No Subject',
      status: 'queued',
      status_details: build_status_details(msg[:variables]).merge(batch_id: batch_id)
    )

    attach_template(email_log)
    email_log
  end
end

