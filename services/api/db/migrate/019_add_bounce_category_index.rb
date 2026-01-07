# frozen_string_literal: true

class AddBounceCategoryIndex < ActiveRecord::Migration[7.1]
  def up
    # Проверяем, что таблица существует и индекс еще не создан
    if table_exists?(:bounced_emails) && !index_exists?(:bounced_emails, :bounce_category, name: 'idx_bounced_emails_bounce_category')
      add_index :bounced_emails, :bounce_category, name: 'idx_bounced_emails_bounce_category'
    end
  end

  def down
    # Удаляем индекс только если он существует
    if index_exists?(:bounced_emails, :bounce_category, name: 'idx_bounced_emails_bounce_category')
      remove_index :bounced_emails, name: 'idx_bounced_emails_bounce_category'
    end
  end
end


