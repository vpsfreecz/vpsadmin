class MailLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :mail_template
  belongs_to :mail_transaction, class_name: 'Transaction', foreign_key: :transaction_id
end
