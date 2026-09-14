require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260914120000_add_new_device_email_verification')

RSpec.describe AddNewDeviceEmailVerification do
  before do
    define_schema do
      create_table :users do |t|
        t.string :login
      end
      create_table :oauth2_authorizations
    end
  end

  it 'keeps existing accounts opted out and creates unique shared rate buckets' do
    insert_row(:users, login: 'existing-member')
    migrate_up!
    expect(column(:users, :enable_new_device_email_verification)).to have_attributes(
      type: :boolean, null: false, default: false
    )
    expect(connection.select_value('SELECT enable_new_device_email_verification FROM users')).to eq(0)
    expect(column(:oauth2_authorizations, :login_authentication).type).to eq(:text)
    bucket = { bucket: 'send:user:1:900', window_start: Time.utc(2026, 9, 14, 12),
               expires_at: Time.utc(2026, 9, 14, 12, 15), count: 1 }
    insert_row(:email_login_rate_limits, bucket)
    expect { insert_row(:email_login_rate_limits, bucket) }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'rolls back the additive schema while retaining account data' do
    insert_row(:users, login: 'existing-member')
    migrate_up!
    migrate_down!
    expect(column_exists?(:users, :enable_new_device_email_verification)).to be(false)
    expect(column_exists?(:oauth2_authorizations, :login_authentication)).to be(false)
    expect(connection.table_exists?(:email_login_rate_limits)).to be(false)
    expect(connection.select_value('SELECT login FROM users')).to eq('existing-member')
  end
end
