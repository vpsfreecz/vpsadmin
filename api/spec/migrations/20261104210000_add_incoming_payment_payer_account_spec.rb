# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_plugin_migration('payments', '20261104210000_add_incoming_payment_payer_account')

RSpec.describe AddIncomingPaymentPayerAccount do
  before do
    define_schema do
      create_table :incoming_payments do |t|
        t.string :transaction_id
      end
    end
    connection.execute("INSERT INTO incoming_payments (transaction_id) VALUES ('previous-payment')")
  end

  it 'leaves the payer account empty for previously imported payments' do
    migrate_up!
    expect(connection.select_value('SELECT payer_account FROM incoming_payments')).to be_nil

    migrate_down!
    expect(column_exists?(:incoming_payments, :payer_account)).to be(false)
  end
end
