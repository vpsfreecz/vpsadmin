class AddPasswordRecovery < ActiveRecord::Migration[8.1]
  def change
    add_column :oauth2_clients, :authorization_start_uri, :string
    add_index :users, :email

    create_table :password_recovery_submissions do |t|
      t.string :identifier, limit: 127, null: false
      t.string :locale, limit: 16, null: false
      t.bigint :oauth2_client_id
      t.string :client_ip_addr, limit: 46
      t.text :user_agent
      t.datetime :processing_started_at
      t.integer :attempts, null: false, default: 0
      t.timestamps
    end

    add_index :password_recovery_submissions,
              %i[processing_started_at attempts created_at],
              name: 'password_recovery_submissions_pending'
    add_index :password_recovery_submissions, :created_at
    add_index :password_recovery_submissions,
              %i[client_ip_addr created_at],
              name: 'password_recovery_submissions_source'
    add_index :password_recovery_submissions, :oauth2_client_id

    create_table :password_recovery_requests do |t|
      t.string :recipient_email, limit: 127, null: false
      t.string :recipient_digest, limit: 64, null: false
      t.string :locale, limit: 16, null: false
      t.bigint :oauth2_client_id
      t.bigint :password_recovery_submission_id
      t.integer :mail_log_id, unsigned: true
      t.string :client_ip_addr, limit: 46
      t.text :user_agent
      t.timestamps
    end

    add_index :password_recovery_requests,
              %i[recipient_digest created_at],
              name: 'password_recovery_requests_throttle'
    add_index :password_recovery_requests, :created_at
    add_index :password_recovery_requests, :oauth2_client_id
    add_index :password_recovery_requests,
              :password_recovery_submission_id,
              unique: true,
              name: 'password_recovery_requests_submission'
    add_index :password_recovery_requests, :mail_log_id, unique: true

    create_table :password_recoveries do |t|
      t.references :password_recovery_request,
                   null: false,
                   index: { name: 'password_recoveries_request' }
      t.integer :user_id, unsigned: true, null: false
      t.integer :outcome, null: false
      t.string :email_snapshot, limit: 127, null: false
      t.string :email_token_digest, limit: 64
      t.string :session_token_digest, limit: 64
      t.datetime :email_expires_at
      t.datetime :session_expires_at
      t.datetime :email_consumed_at
      t.datetime :mfa_verified_at
      t.datetime :completed_at
      t.datetime :invalidated_at
      t.integer :totp_failed_attempts, null: false, default: 0
      t.timestamps
    end

    add_index :password_recoveries, :user_id
    add_index :password_recoveries, :email_token_digest, unique: true
    add_index :password_recoveries, :session_token_digest, unique: true
    add_index :password_recoveries,
              %i[user_id completed_at invalidated_at],
              name: 'password_recoveries_active_user'

    add_column :webauthn_challenges, :password_recovery_id, :bigint
    add_index :webauthn_challenges, :password_recovery_id
  end
end
