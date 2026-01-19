# frozen_string_literal: true

class AddSentFailedToTrackingEventsCheck < ActiveRecord::Migration[7.1]
  def up
    # Remove old CHECK constraint
    execute <<-SQL
      ALTER TABLE tracking_events DROP CONSTRAINT IF EXISTS tracking_events_type_check;
    SQL

    # Add new CHECK constraint with sent and failed
    execute <<-SQL
      ALTER TABLE tracking_events ADD CONSTRAINT tracking_events_type_check
      CHECK (event_type::text = ANY (ARRAY['open', 'click', 'bounce', 'complaint', 'delivered', 'unsubscribe', 'sent', 'failed']::text[]));
    SQL
  end

  def down
    execute <<-SQL
      ALTER TABLE tracking_events DROP CONSTRAINT IF EXISTS tracking_events_type_check;
    SQL

    execute <<-SQL
      ALTER TABLE tracking_events ADD CONSTRAINT tracking_events_type_check
      CHECK (event_type::text = ANY (ARRAY['open', 'click', 'bounce', 'complaint', 'delivered', 'unsubscribe']::text[]));
    SQL
  end
end
