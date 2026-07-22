# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260722120200_add_user_notification_delivery_methods')

RSpec.describe AddUserNotificationDeliveryMethods do
  def define_users_schema
    define_schema do
      create_table :users do |t|
        t.string :login
        t.boolean :mailer_enabled, null: false, default: true
      end
    end
  end

  it 'creates delivery method settings and preserves disabled mailers' do
    define_users_schema
    insert_row(:users, login: 'enabled', mailer_enabled: true)
    disabled_id = insert_row(:users, login: 'disabled', mailer_enabled: false)

    migrate_up!

    expect(table_exists?(:user_notification_delivery_methods)).to be(true)
    expect(index_exists?(:user_notification_delivery_methods,
                         :idx_user_notification_delivery_methods_unique)).to be(true)
    expect(index_exists?(:user_notification_delivery_methods,
                         :idx_user_notification_delivery_methods_state)).to be(true)

    method = find_row(:user_notification_delivery_methods, user_id: disabled_id)
    expect(method.fetch('delivery_method')).to eq('email')
    expect(boolish(method.fetch('enabled'))).to be(false)
    expect(row_count(:user_notification_delivery_methods)).to eq(1)
  end

  it 'drops the delivery method settings table on rollback' do
    define_users_schema
    migrate_up!

    migrate_down!

    expect(table_exists?(:user_notification_delivery_methods)).to be(false)
  end
end
