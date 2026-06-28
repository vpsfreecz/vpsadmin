# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260622161000_convert_notification_action_columns_to_strings')

RSpec.describe ConvertNotificationActionColumnsToStrings do
  def define_action_schema(type:)
    define_schema do
      create_table :notification_targets do |t|
        t.column :action, type, null: false
      end

      create_table :event_deliveries do |t|
        t.column :action, type, null: false
      end

      create_table :event_delivery_attempts do |t|
        t.column :action, type, null: false
      end
    end
  end

  it 'converts known integer actions to string identifiers' do
    define_action_schema(type: :integer)
    insert_row(:notification_targets, action: 0)
    insert_row(:event_deliveries, action: 1)
    insert_row(:event_delivery_attempts, action: 2)

    migrate_up!

    expect(column(:notification_targets, :action).type).to eq(:string)
    expect(rows(:notification_targets).first.fetch('action')).to eq('email')
    expect(rows(:event_deliveries).first.fetch('action')).to eq('webhook')
    expect(rows(:event_delivery_attempts).first.fetch('action')).to eq('telegram')
  end

  it 'rolls known string identifiers back to integers' do
    define_action_schema(type: :string)
    insert_row(:notification_targets, action: 'email')
    insert_row(:event_deliveries, action: 'webhook')
    insert_row(:event_delivery_attempts, action: 'telegram')

    migrate_down!

    expect(column(:notification_targets, :action).type).to eq(:integer)
    expect(rows(:notification_targets).first.fetch('action').to_i).to eq(0)
    expect(rows(:event_deliveries).first.fetch('action').to_i).to eq(1)
    expect(rows(:event_delivery_attempts).first.fetch('action').to_i).to eq(2)
  end

  it 'refuses to roll back unknown string identifiers' do
    define_action_schema(type: :string)
    insert_row(:notification_targets, action: 'email')
    insert_row(:event_deliveries, action: 'sms')
    insert_row(:event_delivery_attempts, action: 'telegram')

    expect { migrate_down! }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
