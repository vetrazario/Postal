class EmailTemplate < ApplicationRecord
  has_many :email_logs, foreign_key: :template_id, dependent: :nullify

  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true, length: { maximum: 255 }
  validates :html_content, presence: true

  scope :active, -> { where(active: true) }

  def self.find_by_external_id(external_id)
    find_by(external_id: external_id)
  end

  def render(variables = {})
    Liquid::Template.parse(html_content).render(variables.stringify_keys)
  rescue Liquid::Error => e
    Rails.logger.error("Template render error: #{e.message}")
    html_content
  end
end

