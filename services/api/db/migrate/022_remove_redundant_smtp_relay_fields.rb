# frozen_string_literal: true

class RemoveRedundantSmtpRelayFields < ActiveRecord::Migration[7.1]
  def change
    # Удаляем дублирующие колонки из system_configs
    # Эти колонки были добавлены в миграциях 017 и 020,
    # но дублируют функционал с smtp_relay_secret_encrypted

    remove_column :system_configs, :smtp_relay_username, if_exists: true
    remove_column :system_configs, :smtp_relay_password_encrypted, if_exists: true
    remove_column :system_configs, :smtp_relay_secret_encrypted, if_exists: true
  end
end
