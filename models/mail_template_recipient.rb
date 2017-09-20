class MailTemplateRecipient < ActiveRecord::Base
  belongs_to :mail_template
  belongs_to :mail_recipient
end
