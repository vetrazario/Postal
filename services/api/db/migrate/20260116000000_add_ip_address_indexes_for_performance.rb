class AddIpAddressIndexesForPerformance < ActiveRecord::Migration[7.0]
  def up
    # Add partial indexes for NULL ip_address checks
    # These optimize the race condition prevention queries:
    # WHERE id = ? AND ip_address IS NULL
    
    # For email_clicks
    execute <<-SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_email_clicks_null_ip 
      ON email_clicks(id) 
      WHERE ip_address IS NULL;
    SQL
    
    # For email_opens  
    execute <<-SQL
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_email_opens_null_ip 
      ON email_opens(id) 
      WHERE ip_address IS NULL;
    SQL
  end

  def down
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_email_clicks_null_ip;"
    execute "DROP INDEX CONCURRENTLY IF EXISTS idx_email_opens_null_ip;"
  end
end
