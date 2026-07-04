# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260703120000_add_czech_language')

RSpec.describe AddCzechLanguage do
  def define_languages_schema
    define_schema do
      create_table :languages do |t|
        t.string :code, limit: 2, null: false
        t.string :label, limit: 100, null: false

        t.index :code, unique: true, name: 'index_languages_on_code'
      end
    end

    described_class::Language.reset_column_information
  end

  it 'creates the Czech language row when missing' do
    define_languages_schema

    migrate_up!

    row = find_row(:languages, code: 'cs')
    expect(row.fetch('label')).to eq('Česky')
    expect(row_count(:languages)).to eq(1)
  end

  it 'updates an existing placeholder label in place' do
    define_languages_schema
    id = insert_row(:languages, code: 'cs', label: 'cs')

    migrate_up!

    row = find_row(:languages, code: 'cs')
    expect(row.fetch('id').to_i).to eq(id)
    expect(row.fetch('label')).to eq('Česky')
    expect(row_count(:languages)).to eq(1)
  end

  it 'keeps an existing translated label' do
    define_languages_schema
    id = insert_row(:languages, code: 'cs', label: 'Čeština')

    migrate_up!

    row = find_row(:languages, code: 'cs')
    expect(row.fetch('id').to_i).to eq(id)
    expect(row.fetch('label')).to eq('Čeština')
    expect(row_count(:languages)).to eq(1)
  end

  it 'keeps the language row on rollback' do
    define_languages_schema
    insert_row(:languages, code: 'cs', label: 'Česky')

    migrate_down!

    row = find_row(:languages, code: 'cs')
    expect(row.fetch('label')).to eq('Česky')
  end

  it 'is idempotent' do
    define_languages_schema

    migrate_up!
    migrate_up!

    row = find_row(:languages, code: 'cs')
    expect(row.fetch('label')).to eq('Česky')
    expect(row_count(:languages, code: 'cs')).to eq(1)
  end
end
