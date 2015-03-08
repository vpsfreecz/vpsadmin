class MailRecipient < ActiveRecord::Base
  has_many :mail_template_recipients
  has_many :mail_templates, through: :mail_template_recipients
end
