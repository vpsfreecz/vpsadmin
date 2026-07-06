# frozen_string_literal: true

require 'json'

require_relative '../migration_helper'

MigrationSpecSupport.require_plugin_migration('webui', '20260706211000_localize_webui_sysconfig')

RSpec.describe LocalizeWebuiSysconfig do
  def define_sysconfig_schema(localized: true)
    define_schema do
      create_table :sysconfig do |t|
        t.string :category, null: false, limit: 75
        t.string :name, null: false, limit: 75
        t.string :data_type, null: false, default: 'Text'
        t.text :value
        t.string :label
        t.text :description
        t.integer :min_user_level
        t.boolean :localized, null: false, default: false if localized
        t.timestamps

        t.index %i[category name], unique: true
      end
    end
  end

  def insert_sysconfig(name, value, data_type: 'Text')
    insert_row(
      :sysconfig,
      category: 'webui',
      name: name.to_s,
      data_type:,
      value:,
      min_user_level: 0,
      created_at: timestamp,
      updated_at: timestamp
    )
  end

  it 'wraps localized WebUI settings in English hashes' do
    define_sysconfig_schema
    insert_sysconfig(:noticeboard, 'Notice')
    insert_sysconfig(:index_info_box_title, JSON.dump('Info'), data_type: 'String')
    insert_sysconfig(:index_info_box_content, 'Content')

    migrate_up!

    noticeboard = find_row(:sysconfig, category: 'webui', name: 'noticeboard')
    expect(noticeboard.fetch('data_type')).to eq('Hash')
    expect(JSON.parse(noticeboard.fetch('value'))).to eq('en' => 'Notice')
    expect(boolish(noticeboard.fetch('localized'))).to be(true)

    title = find_row(:sysconfig, category: 'webui', name: 'index_info_box_title')
    expect(title.fetch('data_type')).to eq('Hash')
    expect(JSON.parse(title.fetch('value'))).to eq('en' => 'Info')
    expect(boolish(title.fetch('localized'))).to be(true)

    sidebar = find_row(:sysconfig, category: 'webui', name: 'sidebar')
    expect(sidebar.fetch('data_type')).to eq('Hash')
    expect(JSON.parse(sidebar.fetch('value'))).to eq({})
    expect(boolish(sidebar.fetch('localized'))).to be(true)
  end

  it 'restores scalar values on rollback' do
    define_sysconfig_schema
    insert_sysconfig(:noticeboard, 'Notice')

    migrate_up!

    row = find_row(:sysconfig, category: 'webui', name: 'noticeboard')
    connection.update(<<~SQL.squish)
      UPDATE sysconfig
      SET value = #{connection.quote(JSON.dump('en' => 'English', 'cs' => 'Cesky'))}
      WHERE id = #{row.fetch('id')}
    SQL

    migrate_down!

    row = find_row(:sysconfig, category: 'webui', name: 'noticeboard')
    expect(row.fetch('data_type')).to eq('Text')
    expect(JSON.parse(row.fetch('value'))).to eq('English')
    expect(boolish(row.fetch('localized'))).to be(false)
  end

  it 'works before the localized metadata column is present' do
    define_sysconfig_schema(localized: false)
    insert_sysconfig(:noticeboard, 'Notice')

    migrate_up!

    noticeboard = find_row(:sysconfig, category: 'webui', name: 'noticeboard')
    expect(noticeboard.fetch('data_type')).to eq('Hash')
    expect(JSON.parse(noticeboard.fetch('value'))).to eq('en' => 'Notice')
  end
end
