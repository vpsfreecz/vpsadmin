class LocalizeNewsLogMessages < ActiveRecord::Migration[8.1]
  class NewsLog < ActiveRecord::Base
    self.table_name = 'news_logs'
  end

  class Language < ActiveRecord::Base
    self.table_name = 'languages'
  end

  class NewsLogTranslation < ActiveRecord::Base
    self.table_name = 'news_log_translations'
  end

  def up
    create_table :news_log_translations do |t|
      t.references :news_log, null: false, index: false
      t.references :language, null: false, index: false
      t.text :message, null: false
      t.timestamps
    end

    add_index :news_log_translations, :news_log_id
    add_index :news_log_translations, :language_id
    add_index :news_log_translations, %i[news_log_id language_id],
              unique: true,
              name: 'news_log_translation_unique'

    english = Language.find_by(code: 'en')
    return unless english

    now = Time.now
    NewsLog.reset_column_information
    NewsLogTranslation.reset_column_information

    NewsLog.find_each do |log|
      next if log.message.blank?

      NewsLogTranslation.create!(
        news_log_id: log.id,
        language_id: english.id,
        message: log.message,
        created_at: log.created_at || now,
        updated_at: log.updated_at || now
      )
    end
  end

  def down
    return unless table_exists?(:news_log_translations)

    english = Language.find_by(code: 'en')
    NewsLog.reset_column_information
    NewsLogTranslation.reset_column_information

    NewsLog.find_each do |log|
      translation = NewsLogTranslation.where(
        news_log_id: log.id,
        language_id: english&.id
      ).take
      translation ||= NewsLogTranslation.where(news_log_id: log.id).order(:id).take

      log.update_columns(message: translation.message) if translation
    end

    drop_table :news_log_translations
  end
end
