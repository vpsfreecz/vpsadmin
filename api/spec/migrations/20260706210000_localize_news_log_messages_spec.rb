# frozen_string_literal: true

require_relative '../migration_helper'

MigrationSpecSupport.require_plugin_migration('newslog', '20260706210000_localize_news_log_messages')

RSpec.describe LocalizeNewsLogMessages do
  def define_news_log_schema
    define_schema do
      create_table :languages do |t|
        t.string :code, limit: 2, null: false
        t.string :label, limit: 100, null: false
      end

      create_table :news_logs do |t|
        t.text :message, null: false
        t.datetime :published_at, null: false
        t.timestamps
      end
    end

    described_class::Language.reset_column_information
    described_class::NewsLog.reset_column_information
  end

  it 'creates translation rows from existing English messages' do
    define_news_log_schema
    language_id = insert_row(:languages, code: 'en', label: 'English')
    news_id = insert_row(
      :news_logs,
      message: 'Hello',
      published_at: timestamp,
      created_at: timestamp,
      updated_at: timestamp
    )

    migrate_up!

    expect(table_exists?(:news_log_translations)).to be(true)
    expect(index_exists?(:news_log_translations, %i[news_log_id language_id])).to be(true)

    row = find_row(:news_log_translations, news_log_id: news_id, language_id:)
    expect(row.fetch('message')).to eq('Hello')
  end

  it 'restores English translation to the legacy message column on rollback' do
    define_news_log_schema
    language_id = insert_row(:languages, code: 'en', label: 'English')
    news_id = insert_row(
      :news_logs,
      message: 'Original',
      published_at: timestamp,
      created_at: timestamp,
      updated_at: timestamp
    )
    migrate_up!

    connection.update(<<~SQL.squish)
      UPDATE news_log_translations
      SET message = 'Updated English'
      WHERE news_log_id = #{news_id} AND language_id = #{language_id}
    SQL

    migrate_down!

    expect(table_exists?(:news_log_translations)).to be(false)
    row = find_row(:news_logs, id: news_id)
    expect(row.fetch('message')).to eq('Updated English')
  end
end
