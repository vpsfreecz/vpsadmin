class Outage < ActiveRecord::Base
  belongs_to :last_report, class_name: 'OutageReport'
  has_many :outage_entities
  has_many :outage_handlers
  has_many :outage_reports
  
  enum state: %i(staged announced closed cancelled)
  enum outage_type: %i(tbd restart reset network performance maintenance)

  after_initialize :load_translations

  # TODO: pick a different method name?
  def self.create!(attrs, translations = {})
    transaction do
      outage = new(attrs)
      outage.save!

      attrs.delete(:planned)

      report = ::OutageReport.new(attrs)
      report.outage = outage
      report.state = 'staged'
      report.reported_by = ::User.current
      report.save!
      
      translations.each do |lang, attrs|
        tr = ::OutageTranslation.new(attrs)
        tr.language = lang
        tr.outage_report = report
        tr.save!
      end
      
      outage.last_report = report
      outage.save!
      outage.load_translations
      outage
    end
  end
  
  # TODO: pick a different method name?
  def update!(attrs = {}, translations = {})
    VpsAdmin::API::Plugins::OutageReports::TransactionChains::Update.fire(
        self,
        attrs,
        translations
    )
  end

  # TODO: check that we have outage entities, handlers and description
  def announce!
    update!(state: ::OutageReport.states[:announced])
  end

  def close!
    update!(state: ::OutageReport.states[:closed])
  end

  def cancel!
    update!(state: ::OutageReport.states[:cancelled])
  end

  def load_translations
    return unless last_report

    last_report.outage_translations.each do |tr|
      %i(summary description).each do |param|
        define_singleton_method("#{tr.language.code}_#{param}") do
          tr.send(param)
        end
      end
    end
  end
end
