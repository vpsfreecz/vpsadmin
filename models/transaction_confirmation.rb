class TransactionConfirmation < ActiveRecord::Base
  belongs_to :parent_transaction, class_name: 'Transaction', foreign_key: :transaction_id

  enum confirm_type: %i(create_type edit_before_type edit_after_type destroy_type
                        just_destroy_type decrement_type increment_type)
  serialize :row_pks
  serialize :attr_changes
end
