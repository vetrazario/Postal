class EmailTemplate < ApplicationRecord
  has_many :email_logs, foreign_key: :template_id, dependent: :nullify

  validates :external_id, uniqueness: true, allow_nil: true
  validates :name, presence: true, length: { maximum: 255 }
  validates :subject, presence: true
  validates :html_body, presence: true

  def self.find_by_external_id(external_id)
    return nil if external_id.blank?
    find_by(external_id: external_id)
  end

  def render(variables = {})
    Liquid::Template.parse(html_body).render(variables.stringify_keys)
  rescue Liquid::Error => e
    Rails.logger.error("Template render error: #{e.message}")
    html_body
  end
end

