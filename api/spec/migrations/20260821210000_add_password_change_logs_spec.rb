# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260821210000_add_password_change_logs')

RSpec.describe AddPasswordChangeLogs do
  before do
    define_schema do
      create_table :oauth2_authorizations
    end
  end

  it 'adds the password change history table' do
    migrate_up!

    expect(table_exists?(:password_change_logs)).to be(true)
    expect(column(:password_change_logs, :user_id)).to have_attributes(
      type: :integer,
      null: false,
      unsigned?: true
    )
    expect(column(:password_change_logs, :user_session_id)).to have_attributes(
      type: :integer,
      null: true,
      unsigned?: true
    )
    expect(column(:password_change_logs, :client_ip_addr)).to have_attributes(
      type: :string,
      limit: 46,
      null: true
    )
    expect(column(:password_change_logs, :client_ip_ptr)).to have_attributes(
      type: :string,
      limit: 255,
      null: true
    )
    expect(column(:password_change_logs, :user_agent_id)).to have_attributes(
      type: :integer,
      null: true
    )
    expect(column(:password_change_logs, :source)).to have_attributes(
      type: :string,
      limit: 32,
      null: false
    )
    expect(column(:password_change_logs, :created_at)).to have_attributes(
      type: :datetime,
      null: false
    )
    expect(index_exists?(:password_change_logs, :password_change_logs_user)).to be(true)
    expect(index_exists?(:password_change_logs, :password_change_logs_user_source)).to be(true)
    expect(
      index_exists?(:password_change_logs, :index_password_change_logs_on_user_session_id)
    ).to be(true)
    expect(
      index_exists?(:password_change_logs, :index_password_change_logs_on_user_agent_id)
    ).to be(true)
    expect(column(:oauth2_authorizations, :password_change_log_id)).to have_attributes(
      type: :integer,
      null: true
    )
    expect(
      index_exists?(:oauth2_authorizations, :index_oauth2_authorizations_on_password_change_log_id)
    ).to be(true)
    oauth_index = connection.indexes(:oauth2_authorizations).find do |candidate|
      candidate.name == 'index_oauth2_authorizations_on_password_change_log_id'
    end
    expect(oauth_index.unique).to be(true)
  end

  it 'removes the password change history table on rollback' do
    migrate_up!

    migrate_down!

    expect(table_exists?(:password_change_logs)).to be(false)
    expect(column_exists?(:oauth2_authorizations, :password_change_log_id)).to be(false)
  end
end
