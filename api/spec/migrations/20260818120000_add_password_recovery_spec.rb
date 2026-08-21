# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260818120000_add_password_recovery')

RSpec.describe AddPasswordRecovery do
  before do
    define_schema do
      create_table :oauth2_clients

      create_table :users, id: { type: :integer, unsigned: true } do |t|
        t.string :email, limit: 127, null: false
      end

      create_table :mail_logs, id: { type: :integer, unsigned: true }
      create_table :webauthn_challenges
    end
  end

  it 'adds recovery state, lookup indexes, and OAuth client configuration' do
    migrate_up!

    expect(column_exists?(:oauth2_clients, :authorization_start_uri)).to be(true)
    expect(column(:oauth2_clients, :authorization_start_requires_user_action)).to have_attributes(
      type: :boolean,
      null: false,
      default: false
    )
    expect(index_exists?(:users, [:email])).to be(true)
    expect(table_exists?(:password_recovery_submissions)).to be(true)
    expect(table_exists?(:password_recovery_requests)).to be(true)
    expect(table_exists?(:password_recoveries)).to be(true)
    expect(column(:password_recovery_requests, :mail_log_id)).to have_attributes(
      type: :integer,
      null: true,
      unsigned?: true
    )
    expect(column(:password_recovery_submissions, :identifier)).to have_attributes(
      type: :string,
      null: true
    )
    expect(column(:password_recovery_submissions, :identifier_digest)).to have_attributes(
      type: :string,
      null: false
    )
    expect(column_exists?(:password_recovery_submissions, :finished_at)).to be(true)
    expect(column(:password_recoveries, :user_id)).to have_attributes(
      type: :integer,
      null: false,
      unsigned?: true
    )
    expect(column_exists?(:webauthn_challenges, :password_recovery_id)).to be(true)
    expect(index_exists?(:password_recovery_requests, [:created_at])).to be(true)
    expect(index_exists?(:password_recovery_submissions, 'password_recovery_submissions_pending'))
      .to be(true)
    expect(index_exists?(:password_recovery_submissions, [:created_at])).to be(true)
    expect(index_exists?(:password_recovery_submissions,
                         'password_recovery_submissions_source')).to be(true)
    expect(index_exists?(:password_recovery_submissions,
                         'password_recovery_submissions_identifier')).to be(true)
    expect(index_exists?(:password_recovery_requests,
                         'password_recovery_requests_submission')).to be(true)
    expect(index_exists?(:password_recoveries, [:email_token_digest])).to be(true)
    expect(index_exists?(:password_recoveries, [:session_token_digest])).to be(true)
  end

  it 'removes all recovery schema on rollback' do
    migrate_up!

    migrate_down!

    expect(table_exists?(:password_recovery_requests)).to be(false)
    expect(table_exists?(:password_recoveries)).to be(false)
    expect(table_exists?(:password_recovery_submissions)).to be(false)
    expect(column_exists?(:oauth2_clients, :authorization_start_uri)).to be(false)
    expect(column_exists?(:oauth2_clients,
                          :authorization_start_requires_user_action)).to be(false)
    expect(column_exists?(:webauthn_challenges, :password_recovery_id)).to be(false)
    expect(index_exists?(:users, [:email])).to be(false)
  end
end
