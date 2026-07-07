# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260707140000_add_sysconfig_localized')

RSpec.describe AddSysconfigLocalized do
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
        t.timestamps

        t.index %i[category name], unique: true
      end
    end
  end

  def insert_sysconfig(category, name, data_type: 'Text')
    insert_row(
      :sysconfig,
      category:,
      name:,
      data_type:,
      value: '',
      min_user_level: 0,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  it 'adds localized metadata and marks known localized settings' do
    define_sysconfig_schema
    insert_sysconfig('webui', 'noticeboard')
    insert_sysconfig('webui', 'sidebar')
    insert_sysconfig('plugin_payments', 'payment_instructions')
    insert_sysconfig('plugin_payments', 'conversion_rates', data_type: 'Hash')
    insert_sysconfig('dns', 'protected_zones', data_type: 'Array')

    migrate_up!

    expect(column_exists?(:sysconfig, :localized)).to be(true)
    expect(column(:sysconfig, :localized).default).to be(false)

    noticeboard = find_row(:sysconfig, category: 'webui', name: 'noticeboard')
    expect(boolish(noticeboard.fetch('localized'))).to be(true)

    sidebar = find_row(:sysconfig, category: 'webui', name: 'sidebar')
    expect(boolish(sidebar.fetch('localized'))).to be(true)

    instructions = find_row(
      :sysconfig,
      category: 'plugin_payments',
      name: 'payment_instructions'
    )
    expect(boolish(instructions.fetch('localized'))).to be(true)

    rates = find_row(:sysconfig, category: 'plugin_payments', name: 'conversion_rates')
    expect(boolish(rates.fetch('localized'))).to be(false)

    protected_zones = find_row(:sysconfig, category: 'dns', name: 'protected_zones')
    expect(boolish(protected_zones.fetch('localized'))).to be(false)
  end

  it 'removes localized metadata on rollback' do
    define_sysconfig_schema
    migrate_up!

    migrate_down!

    expect(column_exists?(:sysconfig, :localized)).to be(false)
  end
end
