class NewsLog < ApplicationRecord
  DEFAULT_LANGUAGE_CODE = 'en'.freeze

  has_many :news_log_translations, dependent: :delete_all

  validates :message, :published_at, presence: true

  after_initialize :load_translations

  def self.translations_available?
    connection.data_source_exists?('news_log_translations')
  rescue ActiveRecord::StatementInvalid
    false
  end

  def localized_message(locale = ::I18n.locale)
    return message unless self.class.translations_available?

    message_for_language(locale, fallback: true)
  end

  def message_for_language(locale, fallback: false)
    code = self.class.language_code(locale)
    messages = translation_messages
    msg = messages[code]

    return msg if msg.present?
    return message if !fallback && code == DEFAULT_LANGUAGE_CODE
    return '' unless fallback

    messages[DEFAULT_LANGUAGE_CODE].presence || messages.values.find(&:present?) || message
  end

  def update_translations!(translations)
    unless self.class.translations_available?
      update_default_message_without_translations!(translations)
      return
    end

    transaction do
      translations.each do |lang, tr_attrs|
        value = tr_attrs.fetch(:message)

        if lang.code == DEFAULT_LANGUAGE_CODE
          self.message = value
          save!
        elsif value.blank?
          news_log_translations.where(language: lang).delete_all
          next
        end

        tr = news_log_translations.find_or_initialize_by(language: lang)
        tr.message = value
        tr.save!
      end
    end

    @translation_messages = nil
    load_translations
  end

  def update_default_message_without_translations!(translations)
    translations.each do |lang, tr_attrs|
      next unless lang.code == DEFAULT_LANGUAGE_CODE

      self.message = tr_attrs.fetch(:message)
      save!
      break
    end
  end

  def load_translations
    return if id.nil? || !self.class.translations_available?

    messages = translation_messages

    ::Language.order(:id).each do |lang|
      define_singleton_method("#{lang.code}_message") do
        messages[lang.code].presence || (lang.code == DEFAULT_LANGUAGE_CODE ? message : '')
      end
    end
  end

  def translation_messages
    return {} if id.nil? || !self.class.translations_available?

    @translation_messages ||= news_log_translations.includes(:language).to_h do |tr|
      [tr.language.code, tr.message]
    end
  end

  def self.language_code(locale)
    case locale
    when ::Language
      locale.code.to_s
    else
      locale.to_s.tr('_', '-').split('-').first
    end
  end
end
