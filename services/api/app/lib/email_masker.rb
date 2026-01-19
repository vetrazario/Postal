# frozen_string_literal: true

# Модуль для маскирования email адресов
# Используется для безопасного отображения email в логах и UI
module EmailMasker
  class << self
    # Маскировать email для безопасного логирования
    # Формат: первая буква + звездочки + последняя буква перед @ + домен
    # Пример: user@example.com -> u***r@example.com
    #
    # @param email [String] email адрес для маскирования
    # @return [String] замаскированный email адрес
    def mask_email(email)
      return email if email.blank?

      local, domain = email.split('@', 2)
      return email if local.blank? || domain.blank?

      masked = if local.length <= 2
                  "#{local[0]}***"
                else
                  "#{local[0]}***#{local[-1]}"
                end

      "#{masked}@#{domain}"
    end
  end
end
