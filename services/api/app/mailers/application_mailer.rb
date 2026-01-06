# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch('NOTIFICATION_FROM_EMAIL', 'no-reply@localhost')
  layout 'mailer'
end

