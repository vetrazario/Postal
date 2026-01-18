# frozen_string_literal: true

class AddUnsubscribeToTrackingEventsCheck < ActiveRecord::Migration[7.1]
  def up
    # Remove old CHECK constraint
    execute <<-SQL
      ALTER TABLE tracking_events DROP CONSTRAINT IF EXISTS tracking_events_type_check;
    SQL

    # Add new CHECK constraint with unsubscribe
    execute <<-SQL
      ALTER TABLE tracking_events ADD CONSTRAINT tracking_events_type_check
      CHECK (event_type::text = ANY (ARRAY['open'::character varying, 'click'::character varying, 'bounce'::character varying, 'complaint'::character varying, 'delivered'::character varying, 'unsubscribe'::character varying]::text[]));
    SQL
  end

  def down
    # Revert to old constraint
    execute <<-SQL
      ALTER TABLE tracking_events DROP CONSTRAINT IF EXISTS tracking_events_type_check;
    SQL

    execute <<-SQL
      ALTER TABLE tracking_events ADD CONSTRAINT tracking_events_type_check
      CHECK (event_type::text = ANY (ARRAY['open'::character varying, 'click'::character varying, 'bounce'::character varying, 'complaint'::character varying, 'delivered'::character varying]::text[]));
    SQL
  end
end
