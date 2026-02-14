class MailTemplateRecipient < ApplicationRecord
  belongs_to :mail_template
  belongs_to :mail_recipient

  validates :mail_template, presence: true
  validates :mail_recipient, presence: true
  validates :mail_recipient, uniqueness: { scope: :mail_template }
end
