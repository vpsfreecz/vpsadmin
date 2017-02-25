module VpsAdmin::API::Plugins::OutageReports::TransactionChains
  class Update < ::TransactionChain
    label 'Update'
    allow_empty

    # @param outage [::Outage]
    # @param attrs [Hash] attributes of {::OutageReport}
    # @param translations [Hash] string; `{Language => {summary => '', description => ''}}`
    def link_chain(outage, attrs, translations)
      report = ::OutageReport.new
      
      attrs.each do |k, v|
        report.assign_attributes(k => v) if outage.send(k) != v
      end

      report.outage = outage
      report.reported_by = ::User.current
      report.save!

      translations.each do |lang, attrs|
        tr = ::OutageTranslation.new(attrs)
        tr.language = lang
        tr.outage_report = report
        tr.save!
      end

      outage.assign_attributes(attrs)
      outage.last_report = report
      outage.save!
      outage.load_translations

      # TODO: send e-mails

      outage
    end
  end
end
