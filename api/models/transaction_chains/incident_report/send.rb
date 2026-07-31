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
        event = route_event!(
          'vps.incident_report',
          user: inc.user,
          vps: inc.vps,
          source: inc,
          subject: inc.subject,
          summary: inc.text.to_s.truncate(::Event::MAX_SUMMARY_LENGTH),
          ip_addr: incident_ip_addr(inc),
          parameters: incident_parameters(inc)
        )
        ensure_email_deliveries_queued!(event)
      end
    end

    protected

    def ensure_email_deliveries_queued!(event)
      return if event.nil?

      failed = event
               .event_deliveries
               .where(action: 'email', state: 'failed')
               .order(:id)
               .first
      return unless failed

      raise "failed to queue incident report e-mail delivery: #{failed.error_summary}"
    end

    def incident_parameters(incident)
      {
        subject: incident.subject,
        text: incident.text.to_s.truncate(8192),
        codename: incident.codename,
        ip_addr: incident_ip_addr(incident),
        vps_id: incident.vps_id
      }
    end

    def incident_ip_addr(incident)
      incident.ip_address_assignment&.ip_addr || incident.ip_address&.ip_addr
    end
  end
end
