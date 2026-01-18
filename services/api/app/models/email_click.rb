# frozen_string_literal: true

class EmailClick < ApplicationRecord
  belongs_to :email_log

  # Validations
  validates :email_log_id, presence: true
  validates :url, presence: true
  validates :clicked_at, presence: true
end
