# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260821120000_add_password_event_counters')

RSpec.describe AddPasswordEventCounters do
  it 'adds the aggregate password event table' do
    migrate_up!

    expect(table_exists?(:password_event_counters)).to be(true)
    expect(column(:password_event_counters, :name)).to have_attributes(
      type: :string,
      limit: 64,
      null: false
    )
    expect(column(:password_event_counters, :event_count)).to have_attributes(
      type: :integer,
      null: false,
      default: 0,
      unsigned?: true
    )
    expect(column_exists?(:password_event_counters, :last_occurred_at)).to be(true)
    expect(
      index_exists?(:password_event_counters, :index_password_event_counters_on_name)
    ).to be(true)
  end

  it 'removes the aggregate password event table on rollback' do
    migrate_up!

    migrate_down!

    expect(table_exists?(:password_event_counters)).to be(false)
  end
end
