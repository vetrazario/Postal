class CreateCampaignStats < ActiveRecord::Migration[7.1]
  def change
    create_table :campaign_stats do |t|
      t.string :campaign_id, null: false, limit: 64
      t.integer :total_sent, null: false, default: 0
      t.integer :total_delivered, null: false, default: 0
      t.integer :total_opened, null: false, default: 0
      t.integer :total_clicked, null: false, default: 0
      t.integer :total_bounced, null: false, default: 0
      t.integer :total_complained, null: false, default: 0
      t.integer :total_failed, null: false, default: 0
      t.integer :unique_opened, null: false, default: 0
      t.integer :unique_clicked, null: false, default: 0

      t.timestamps
    end

    add_index :campaign_stats, :campaign_id, unique: true
    
    add_check_constraint :campaign_stats, 
      "total_sent >= 0 AND total_delivered >= 0 AND total_opened >= 0 AND total_clicked >= 0 AND total_bounced >= 0 AND total_complained >= 0 AND total_failed >= 0",
      name: "campaign_stats_positive"
  end
end





