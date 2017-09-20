class RemoveUserPayments < ActiveRecord::Migration
  def change
    remove_column :users, :monthly_payment, :integer, null: false,
        default: 300, unsigned: true
    remove_column :users, :paid_until, :datetime, null: true
  end
end
