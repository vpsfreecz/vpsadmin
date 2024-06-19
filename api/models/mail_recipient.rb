class MailRecipient < ApplicationRecord
  has_many :mail_template_recipients
  has_many :mail_templates, through: :mail_template_recipients

  validates :label, presence: true
end
