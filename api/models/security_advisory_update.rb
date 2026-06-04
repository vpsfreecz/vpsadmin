class SecurityAdvisoryUpdate < ApplicationRecord
  belongs_to :security_advisory
  belongs_to :reported_by, class_name: 'User', optional: true
  has_many :security_advisory_translations, dependent: :delete_all

  enum :state, ::SecurityAdvisory.states

  after_initialize :load_translations
  before_validation :set_reporter_name

  def cves
    security_advisory.cves
  end

  def name
    security_advisory.name
  end

  %i[summary message].each do |attr|
    define_method(attr) do
      tr = security_advisory_translations.find_by(language: ::User.current&.language)
      tr ||= security_advisory_translations.first
      tr ? tr.send(attr) : ''
    end
  end

  def update_translations!(translations)
    transaction do
      translations.each do |lang, tr_attrs|
        tr = security_advisory_translations.find_or_initialize_by(language: lang)
        tr.assign_attributes(tr_attrs)
        tr.save!
      end
    end

    load_translations
  end

  def load_translations
    return if id.nil?

    ::SecurityAdvisoryTranslation.joins(
      'RIGHT JOIN languages ON languages.id = security_advisory_translations.language_id'
    ).where(
      security_advisory_update_id: id
    ).each do |tr|
      lang = tr.language
      next unless lang

      %i[summary message].each do |param|
        define_singleton_method("#{lang.code}_#{param}") do
          tr.send(param)
        end
      end
    end
  end

  protected

  def set_reporter_name
    return if reporter_name.present? || reported_by.nil?

    self.reporter_name = reported_by.full_name
  end
end
