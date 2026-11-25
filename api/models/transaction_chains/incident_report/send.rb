module TransactionChains
  class IncidentReport::Send < ::TransactionChain
    label 'Incident report'
    allow_empty

    # @param result [VpsAdmin::API::IncidentReports::Result]
    # @param message [Mail::Message, nil]
    def link_chain(result, message: nil)
      concerns(:affect, *result.active.map { |v| [v.vps.class.name, v.vps_id] }.uniq)

      use_chain(IncidentReport::Reply, args: [message, result]) if message && result.reply

      result.active.each do |inc|
        template = ::MailTemplate.find_by!(name: 'vps_incident_report')
        translation = ::MailTemplate.mail_template_translation_for(template, inc.user.language)
        raise ::VpsAdmin::API::Exceptions::MailTemplateDoesNotExist, :vps_incident_report unless translation

        mail(:vps_incident_report, {
               user: inc.user, language: translation.language,
               vars: {
                 base_url: ::SysConfig.get(:webui, :base_url),
                 user: inc.user,
                 vps: inc.vps,
                 incident: inc,
                 vps_evidence: VpsAdmin::API::IncidentReports.vps_evidence_mail_projection(inc),
                 incident_policies: VpsAdmin::API::IncidentReports.mail_policies(inc, language: translation.language.code)
               }
             })
      end
    end
  end
end
