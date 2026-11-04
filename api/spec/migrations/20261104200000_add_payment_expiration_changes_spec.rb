# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_plugin_migration('payments', '20261104200000_add_payment_expiration_changes')

RSpec.describe AddPaymentExpirationChanges do
  before do
    define_schema do
      create_table :user_payments do |t|
        t.integer :amount, null: false
        t.datetime :from_date, null: false
        t.datetime :to_date, null: false
      end
    end
    connection.execute("INSERT INTO user_payments (amount, from_date, to_date) VALUES (900, '2027-02-04', '2027-05-04')")
  end

  it 'preserves existing payments and can revert before the first manual change' do
    migrate_up!
    expect(connection.select_value('SELECT expiration_change FROM user_payments')).to eq(0)

    migrate_down!
    expect(column_exists?(:user_payments, :expiration_change)).to be(false)
    expect(connection.select_value('SELECT amount FROM user_payments')).to eq(900)
  end

  it 'preserves history by refusing to discard manual changes on downgrade' do
    migrate_up!
    connection.execute('INSERT INTO user_payments (expiration_change) VALUES (TRUE)')

    expect { migrate_down! }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
