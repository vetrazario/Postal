# frozen_string_literal: true

# DTO (Data Transfer Object) для параметров отправки email
# Позволяет валидировать и нормализовать параметры перед отправкой
class EmailParamsDto
  attr_reader :recipient, :from_name, :from_email, :subject, :template_id,
              :variables, :tracking

  # Создать DTO из параметров запроса
  #
  # @param params [Hash] параметры из запроса
  # @return [EmailParamsDto] DTO с валидированными параметрами
  def self.from_params(params)
    new(
      recipient: params[:recipient],
      from_name: params[:from_name],
      from_email: params[:from_email],
      subject: params[:subject],
      template_id: params[:template_id],
      variables: params[:variables],
      tracking: params[:tracking]
    )
  end

  def initialize(recipient:, from_name: nil, from_email:, subject: nil,
             template_id: nil, variables: nil, tracking: nil)
    @recipient = recipient
    @from_name = from_name
    @from_email = from_email
    @subject = subject
    @template_id = template_id
    @variables = variables
    @tracking = tracking
  end

  # Валидация параметров
  #
  # @return [Hash] результат валидации с ключами :valid и :error
  def validate
    return { valid: false, error: 'Recipient is required' } if recipient.blank?
    return { valid: false, error: 'From email is required' } if from_email.blank?

    email_validation = EmailValidator.validate(recipient: recipient, from_email: from_email)
    return email_validation unless email_validation[:valid]

    { valid: true }
  end

  # Конвертировать в Hash для использования в сервисах
  #
  # @return [Hash] параметры в формате Hash с символами
  def to_h
    {
      recipient: recipient,
      from_name: from_name,
      from_email: from_email,
      subject: subject || 'No Subject',
      template_id: template_id,
      variables: variables || {},
      tracking: tracking || {}
    }.deep_symbolize_keys
  end
end
