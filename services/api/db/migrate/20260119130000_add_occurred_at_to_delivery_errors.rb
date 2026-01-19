class AddOccurredAtToDeliveryErrors < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:delivery_errors, :occurred_at)
      add_column :delivery_errors, :occurred_at, :datetime

      # Заполняем из created_at для существующих записей
      execute "UPDATE delivery_errors SET occurred_at = created_at WHERE occurred_at IS NULL"
    end
  end
end
