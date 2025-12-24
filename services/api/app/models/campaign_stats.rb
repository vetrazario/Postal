class CampaignStats < ApplicationRecord
  validates :campaign_id, presence: true, uniqueness: true
  validates :total_sent, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_delivered, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_opened, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_clicked, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_bounced, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_complained, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_failed, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Find or initialize stats for campaign
  def self.find_or_initialize_for(campaign_id)
    find_or_initialize_by(campaign_id: campaign_id) do |stats|
      stats.total_sent = 0
      stats.total_delivered = 0
      stats.total_opened = 0
      stats.total_clicked = 0
      stats.total_bounced = 0
      stats.total_complained = 0
      stats.total_failed = 0
      stats.unique_opened = 0
      stats.unique_clicked = 0
    end
  end

  # Increment counters (thread-safe)
  def increment_sent
    increment!(:total_sent)
  end

  def increment_delivered
    increment!(:total_delivered)
  end

  def increment_opened
    increment!(:total_opened)
  end

  def increment_clicked
    increment!(:total_clicked)
  end

  def increment_bounced
    increment!(:total_bounced)
  end

  def increment_complained
    increment!(:total_complained)
  end

  def increment_failed
    increment!(:total_failed)
  end
end





