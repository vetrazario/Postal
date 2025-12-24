class ApiKey < ApplicationRecord
  validates :key_hash, presence: true, length: { is: 64 }, uniqueness: true
  validates :name, presence: true
  validates :permissions, presence: true
  validates :rate_limit, presence: true, numericality: { greater_than: 0 }
  validates :daily_limit, presence: true, numericality: { greater_than_or_equal_to: 0 }

  def self.generate(name:, permissions: { send: true, batch: true }, rate_limit: 100, daily_limit: 0)
    raw_key = SecureRandom.hex(24)
    key_hash = Digest::SHA256.hexdigest(raw_key)

    api_key = create!(
      key_hash: key_hash,
      name: name,
      permissions: permissions,
      rate_limit: rate_limit,
      daily_limit: daily_limit
    )

    [api_key, raw_key]
  end

  def touch_last_used
    update_column(:last_used_at, Time.current)
  end

  def has_permission?(permission)
    permissions[permission.to_s] == true || permissions[permission.to_sym] == true
  end
end
