class AddIncomingPaymentPayerAccount < ActiveRecord::Migration[8.1]
  def change
    add_column :incoming_payments, :payer_account, :string
  end
end
