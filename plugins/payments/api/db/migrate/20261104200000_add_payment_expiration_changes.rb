class AddPaymentExpirationChanges < ActiveRecord::Migration[8.1]
  def up
    add_column :user_payments, :expiration_change, :boolean, default: false, null: false
    %i[amount from_date to_date].each { |column| change_column_null :user_payments, column, true }
  end

  def down
    if select_value('SELECT 1 FROM user_payments WHERE expiration_change = TRUE LIMIT 1')
      raise ActiveRecord::IrreversibleMigration, 'The payment history contains manual expiration changes'
    end

    %i[amount from_date to_date].each { |column| change_column_null :user_payments, column, false }
    remove_column :user_payments, :expiration_change
  end
end
