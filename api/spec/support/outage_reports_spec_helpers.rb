# frozen_string_literal: true

module OutageReportsSpecHelpers
  include CoreResourceSpecHelpers

  def create_outage_with_translation!(attrs = {}, summary: 'Spec outage', description: 'Spec description')
    outage = nil
    callbacks = ::Outage._initialize_callbacks
    has_callback = callbacks.any? { |cb| cb.filter == :load_translations }

    ::Outage.skip_callback(:initialize, :after, :load_translations) if has_callback
    outage = ::Outage.create!(attrs)
  ensure
    ::Outage.set_callback(:initialize, :after, :load_translations) if has_callback
    if outage
      lang = ::Language.find_by(code: 'en')
      if lang
        ::OutageTranslation.create!(outage: outage, language: lang, summary: summary, description: description)
      end
      outage.reload
    end
  end
end
