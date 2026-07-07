# frozen_string_literal: true

require 'json'

require_relative '../migration_helper'

MigrationSpecSupport.require_plugin_migration('payments', '20260706212000_localize_payment_instructions_sysconfig')

RSpec.describe LocalizePaymentInstructionsSysconfig do
  def define_sysconfig_schema
    define_schema do
      create_table :sysconfig do |t|
        t.string :category, null: false, limit: 75
        t.string :name, null: false, limit: 75
        t.string :data_type, null: false, default: 'Text'
        t.text :value
        t.string :label
        t.text :description
        t.integer :min_user_level
        t.boolean :localized, null: false, default: false
        t.timestamps

        t.index %i[category name], unique: true
      end
    end
  end

  def insert_payment_instructions(value)
    insert_row(
      :sysconfig,
      category: 'plugin_payments',
      name: 'payment_instructions',
      data_type: 'Text',
      value:,
      label: 'Payment instructions',
      min_user_level: 99,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  it 'wraps existing payment instructions in an English hash' do
    define_sysconfig_schema
    insert_payment_instructions('Pay here')

    migrate_up!

    row = find_row(:sysconfig, category: 'plugin_payments', name: 'payment_instructions')
    expect(row.fetch('data_type')).to eq('Hash')
    expect(JSON.parse(row.fetch('value'))).to eq('en' => 'Pay here')
    expect(boolish(row.fetch('localized'))).to be(true)
  end

  it 'creates the setting when it is missing' do
    define_sysconfig_schema

    migrate_up!

    row = find_row(:sysconfig, category: 'plugin_payments', name: 'payment_instructions')
    expect(row.fetch('data_type')).to eq('Hash')
    expect(row.fetch('label')).to eq('Payment instructions')
    expect(JSON.parse(row.fetch('value'))).to eq({})
    expect(boolish(row.fetch('localized'))).to be(true)
  end

  it 'restores scalar instructions on rollback' do
    define_sysconfig_schema
    insert_payment_instructions('Pay here')
    migrate_up!

    row = find_row(:sysconfig, category: 'plugin_payments', name: 'payment_instructions')
    connection.update(<<~SQL.squish)
      UPDATE sysconfig
      SET value = #{connection.quote(JSON.dump('en' => 'English', 'cs' => 'Cesky'))}
      WHERE id = #{row.fetch('id')}
    SQL

    migrate_down!

    row = find_row(:sysconfig, category: 'plugin_payments', name: 'payment_instructions')
    expect(row.fetch('data_type')).to eq('Text')
    expect(JSON.parse(row.fetch('value'))).to eq('English')
    expect(boolish(row.fetch('localized'))).to be(false)
  end
end
