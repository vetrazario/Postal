# frozen_string_literal: true

# Сервис для проверки блокировок email адресов
# Объединяет проверку на unsubscribe и bounced email в одном месте
class EmailBlocker
  class << self
    # Проверить, заблокирован ли email для отправки
    #
    # @param email [String] email адрес для проверки
    # @param campaign_id [String, nil] идентификатор кампании
    # @return [Hash] результат проверки с ключами :blocked и :reason
    def blocked?(email:, campaign_id: nil)
      return { blocked: true, reason: 'unsubscribed' } if Unsubscribe.blocked?(email: email, campaign_id: campaign_id)
      return { blocked: true, reason: 'bounced' } if BouncedEmail.blocked?(email: email, campaign_id: campaign_id)
      { blocked: false }
    end
  end
end
