class EmailRecipient < ApplicationRecord
  has_many :notification_template_email_recipients
  has_many :notification_templates, through: :notification_template_email_recipients

  validates :label, presence: true
end
