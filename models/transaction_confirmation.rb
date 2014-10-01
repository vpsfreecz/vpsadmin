class TransactionConfirmation < ActiveRecord::Base
  belongs_to :parent_transaction, class_name: 'Transaction', foreign_key: :transaction_id

  enum confirm_type: %i(create_type edit_type destroy_type)
  serialize :row_pks
  serialize :attr_changes
end
