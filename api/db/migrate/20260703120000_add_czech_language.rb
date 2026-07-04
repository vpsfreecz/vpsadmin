class AddCzechLanguage < ActiveRecord::Migration[8.1]
  class Language < ActiveRecord::Base; end

  def up
    language = Language.find_or_initialize_by(code: 'cs')
    language.label = 'Česky' if language.new_record? || language.label == 'cs'
    language.save! if language.changed?
  end

  def down
    # Keep the row: existing users, mail templates, or advisories may reference
    # it once the locale has been enabled.
  end
end
