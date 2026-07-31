class NotificationTemplateEmailRecipient < ApplicationRecord
  belongs_to :notification_template
  belongs_to :email_recipient

  validates :notification_template, presence: true
  validates :email_recipient, presence: true
  validates :email_recipient, uniqueness: { scope: :notification_template }
end
