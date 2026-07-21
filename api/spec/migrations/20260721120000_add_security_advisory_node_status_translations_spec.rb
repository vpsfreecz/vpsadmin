# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_migration('20260721120000_add_security_advisory_node_status_translations')

RSpec.describe AddSecurityAdvisoryNodeStatusTranslations do
  before do
    define_schema do
      create_table :languages do |t|
        t.string :code, null: false
        t.string :label, null: false
      end

      create_table :security_advisory_node_statuses do |t|
        t.text :note
      end
    end
  end

  it 'moves existing English notes into translations and removes the column' do
    english_id = insert_row(:languages, code: 'en', label: 'English')
    insert_row(:languages, code: 'cs', label: 'Česky')
    translated_id = insert_row(:security_advisory_node_statuses, note: 'Mitigated by live patch')
    insert_row(:security_advisory_node_statuses, note: nil)

    migrate_up!

    expect(table_exists?(:security_advisory_node_status_translations)).to be(true)
    expect(index_exists?(
             :security_advisory_node_status_translations,
             'index_sanst_on_status_language'
           )).to be(true)
    expect(column_exists?(:security_advisory_node_statuses, :note)).to be(false)
    expect(rows(:security_advisory_node_status_translations)).to contain_exactly(
      include(
        'security_advisory_node_status_id' => translated_id,
        'language_id' => english_id,
        'note' => 'Mitigated by live patch'
      )
    )
  end

  it 'restores English and loses Czech translations on rollback' do
    insert_row(:languages, code: 'en', label: 'English')
    czech_id = insert_row(:languages, code: 'cs', label: 'Česky')
    status_id = insert_row(:security_advisory_node_statuses, note: 'Legacy note')
    migrate_up!

    insert_row(
      :security_advisory_node_status_translations,
      security_advisory_node_status_id: status_id,
      language_id: czech_id,
      note: 'Česká poznámka'
    )

    migrate_down!

    expect(table_exists?(:security_advisory_node_status_translations)).to be(false)
    expect(column_exists?(:security_advisory_node_statuses, :note)).to be(true)
    expect(find_row(:security_advisory_node_statuses, id: status_id).fetch('note'))
      .to eq('Legacy note')
  end
end
