class AddSecurityAdvisoryNodeStatusTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :security_advisory_node_status_translations do |t|
      t.references :security_advisory_node_status, null: false, index: false
      t.references :language, null: false, index: false
      t.text :note, null: true
    end

    add_index :security_advisory_node_status_translations,
              %i[security_advisory_node_status_id language_id],
              unique: true,
              name: 'index_sanst_on_status_language'
    add_index :security_advisory_node_status_translations,
              :language_id,
              name: 'index_sanst_on_language'

    reversible do |dir|
      dir.up { migrate_english_notes_to_translations }
      dir.down { restore_english_notes }
    end

    remove_column :security_advisory_node_statuses, :note, :text
  end

  protected

  def migrate_english_notes_to_translations
    language_id = english_language_id!
    connection.execute(<<~SQL.squish)
      INSERT INTO #{connection.quote_table_name('security_advisory_node_status_translations')}
        (security_advisory_node_status_id, language_id, note)
      SELECT id, #{connection.quote(language_id)}, note
      FROM #{connection.quote_table_name('security_advisory_node_statuses')}
      WHERE note IS NOT NULL AND note <> ''
    SQL
  end

  def restore_english_notes
    language_id = english_language_id!
    connection.execute(<<~SQL.squish)
      UPDATE #{connection.quote_table_name('security_advisory_node_statuses')} AS statuses
      INNER JOIN #{connection.quote_table_name('security_advisory_node_status_translations')} AS translations
        ON translations.security_advisory_node_status_id = statuses.id
      SET statuses.note = translations.note
      WHERE translations.language_id = #{connection.quote(language_id)}
    SQL
  end

  def english_language_id!
    language_id = connection.select_value(<<~SQL.squish)
      SELECT id
      FROM #{connection.quote_table_name('languages')}
      WHERE code = #{connection.quote('en')}
      LIMIT 1
    SQL
    return language_id if language_id

    raise ActiveRecord::MigrationError, 'English language is required to migrate security advisory Node notes'
  end
end
