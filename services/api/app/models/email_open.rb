# frozen_string_literal: true

class EmailOpen < ApplicationRecord
  belongs_to :email_log

  # Scopes
  scope :unique_opens, -> { select(:email_log_id).distinct }
  
  # Validations
  validates :email_log_id, presence: true
  validates :opened_at, presence: true
end
