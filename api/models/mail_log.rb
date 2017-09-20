class MailLog < ActiveRecord::Base
  belongs_to :user
  belongs_to :mail_template
  belongs_to :mail_transaction, class_name: 'Transaction', foreign_key: :transaction_id
end
