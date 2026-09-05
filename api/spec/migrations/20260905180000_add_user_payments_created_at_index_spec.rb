# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_plugin_migration(
  'payments',
  '20260905180000_add_user_payments_created_at_index'
)

RSpec.describe AddUserPaymentsCreatedAtIndex do
  before do
    define_schema do
      create_table :user_payments do |t|
        t.datetime :created_at
      end
    end
  end

  it 'adds and removes the created_at index' do
    migrate_up!

    expect(index_exists?(:user_payments, [:created_at])).to be(true)

    migrate_down!

    expect(index_exists?(:user_payments, [:created_at])).to be(false)
  end
end
