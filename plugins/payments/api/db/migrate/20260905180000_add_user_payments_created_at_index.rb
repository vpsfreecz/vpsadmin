class AddUserPaymentsCreatedAtIndex < ActiveRecord::Migration[8.1]
  def change
    add_index :user_payments, :created_at
  end
end
