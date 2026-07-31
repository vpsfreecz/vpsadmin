# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260628120000_add_notification_rate_limits')

RSpec.describe AddNotificationRateLimits do
  def define_dependency_schema
    define_schema do
      create_table :users do |t|
        t.string :login
      end

      create_table :event_delivery_attempts do |t|
        t.string :action, null: false
        t.string :state, null: false
        t.integer :attempt_number, null: false
        t.datetime :started_at
        t.datetime :finished_at
        t.timestamps null: false
      end
    end
  end

  it 'adds per-user rate limit overrides, lock states, and attempt indexes' do
    define_dependency_schema
    started_at = timestamp
    attempt_id = insert_row(
      :event_delivery_attempts,
      action: 'webhook',
      state: 'succeeded',
      attempt_number: 1,
      started_at:,
      finished_at: started_at + 1,
      created_at: started_at,
      updated_at: started_at
    )

    migrate_up!

    expect(table_exists?(:user_notification_rate_limits)).to be(true)
    expect(column(:user_notification_rate_limits, :delivery_method).limit).to eq(32)
    expect(column(:user_notification_rate_limits, :period).limit).to eq(16)
    expect(column(:user_notification_rate_limits, :limit_count).null).to be(false)
    expect(index_exists?(:user_notification_rate_limits,
                         :idx_user_notification_rate_limits_unique)).to be(true)
    expect(index_exists?(:user_notification_rate_limits,
                         :idx_user_notification_rate_limits_method_period)).to be(true)

    expect(table_exists?(:notification_rate_limit_states)).to be(true)
    expect(column(:notification_rate_limit_states, :delivery_method).limit).to eq(32)
    expect(index_exists?(:notification_rate_limit_states,
                         :idx_notification_rate_limit_states_unique)).to be(true)

    expect(column_exists?(:event_delivery_attempts, :recipient_user_id)).to be(true)
    expect(column(:event_delivery_attempts, :recipient_user_id).null).to be(true)
    expect(index_exists?(:event_delivery_attempts,
                         :idx_event_delivery_attempts_on_recipient_user)).to be(true)
    expect(index_exists?(:event_delivery_attempts,
                         :idx_delivery_attempts_on_recipient_action_started)).to be(true)

    attempt = find_row(:event_delivery_attempts, id: attempt_id)
    expect(attempt.fetch('recipient_user_id')).to be_nil
  end

  it 'removes rate limit schema additions on rollback' do
    define_dependency_schema
    migrate_up!

    migrate_down!

    expect(table_exists?(:user_notification_rate_limits)).to be(false)
    expect(table_exists?(:notification_rate_limit_states)).to be(false)
    expect(column_exists?(:event_delivery_attempts, :recipient_user_id)).to be(false)
    expect(index_exists?(:event_delivery_attempts,
                         :idx_delivery_attempts_on_recipient_action_started)).to be(false)
  end
end
