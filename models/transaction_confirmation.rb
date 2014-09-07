class TransactionConfirmation < ActiveRecord::Base
  belongs_to :parent_transaction, foreign_key: :transaction_id

  enum confirm_type: %i(create_type edit_type destroy_type)
end
