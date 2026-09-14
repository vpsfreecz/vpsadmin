# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260914120000_add_daily_report_authentication_indexes')

RSpec.describe AddDailyReportAuthenticationIndexes do
  before do
    define_schema do
      create_table :user_sessions do |t|
        t.datetime :created_at, null: false
        t.datetime :closed_at
      end
      create_table :password_change_logs do |t|
        t.datetime :created_at, null: false
      end
      create_table :user_failed_logins do |t|
        t.datetime :created_at, null: false
      end
    end
  end

  it 'adds the report indexes and removes them on rollback without removing data' do
    connection.execute("INSERT INTO user_sessions (created_at) VALUES ('2026-09-14 10:00:00')")
    migrate_up!

    expect(connection.indexes(:user_sessions).map(&:columns)).to contain_exactly(['created_at'], ['closed_at'])
    expect(connection.indexes(:password_change_logs).map(&:columns)).to eq([['created_at']])
    expect(connection.indexes(:user_failed_logins).map(&:columns)).to eq([['created_at']])

    migrate_down!

    expect(connection.indexes(:user_sessions)).to be_empty
    expect(connection.indexes(:password_change_logs)).to be_empty
    expect(connection.indexes(:user_failed_logins)).to be_empty
    expect(connection.select_value('SELECT COUNT(*) FROM user_sessions')).to eq(1)
  end
end
