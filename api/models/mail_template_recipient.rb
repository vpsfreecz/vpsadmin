class MailTemplateRecipient < ApplicationRecord
  belongs_to :mail_template
  belongs_to :mail_recipient
end
