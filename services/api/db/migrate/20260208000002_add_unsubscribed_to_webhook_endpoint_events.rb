class AddUnsubscribedToWebhookEndpointEvents < ActiveRecord::Migration[7.1]
  def up
    # Update existing webhook endpoints to include 'unsubscribed' event
    execute <<~SQL
      UPDATE webhook_endpoints
      SET events = events::jsonb || '["unsubscribed"]'::jsonb
      WHERE NOT (events::jsonb @> '["unsubscribed"]'::jsonb)
    SQL

    # Update default for new records
    change_column_default :webhook_endpoints, :events,
      %w[delivered opened clicked bounced failed complained unsubscribed]
  end

  def down
    change_column_default :webhook_endpoints, :events,
      %w[delivered opened clicked bounced failed complained]
  end
end
