module TransactionChains
  class Vps::IncidentEscalationMail < ::TransactionChain
    label 'Incident escalation notification'
    allow_empty

    def link_chain(action)
      concerns(:affect, ['Vps', action.vps_id])
      rule = ::IncidentEscalation.rule(action.incident_type)
      specific = action.kind == 'stop' ? rule.stopped_template : rule.warning_template
      selected = specific if specific && ::MailTemplate.exists?(name: specific.to_s)
      selected ||= action.kind == 'stop' ? :vps_incident_stopped : :vps_incident_warning
      template = ::MailTemplate.find_by!(name: selected.to_s)
      translation = ::MailTemplate.mail_template_translation_for(template, action.user.language)
      raise ::VpsAdmin::API::Exceptions::MailTemplateDoesNotExist, selected unless translation

      message = mail(selected, {
                       user: action.user, language: translation.language,
                       message_id: action.message_id,
                       vars: ::IncidentEscalation.new(action.vps, incident_type: action.incident_type)
                             .mail_vars(action, language: translation.language.code)
                     })
      unless message
        action.update!(mail_state: 'suppressed', state: action.kind == 'warning' ? 'completed' : action.state, error: nil)
        return
      end

      action.update!(mail_chain_id: current_chain.id, mail_log: message, mail_state: 'queued',
                     state: action.kind == 'warning' ? 'queued' : action.state, error: nil)
    end
  end
end
