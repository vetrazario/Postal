class AddTotalUnsubscribedToCampaignStats < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:campaign_stats, :total_unsubscribed)
      add_column :campaign_stats, :total_unsubscribed, :integer, default: 0, null: false
    end
  end
end
