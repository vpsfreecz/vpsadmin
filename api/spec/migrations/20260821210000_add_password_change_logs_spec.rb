# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260821210000_add_password_change_logs')

RSpec.describe AddPasswordChangeLogs do
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
  end

  it 'removes the password change history table on rollback' do
    migrate_up!

    migrate_down!

    expect(table_exists?(:password_change_logs)).to be(false)
  end
end
