require_relative 'utils'

module TransactionChains
  class IncidentReport::Process < ::TransactionChain
    label 'Incident report'

    include IncidentReport::Utils

    def link_chain(incidents)
      concerns(:affect, *incidents.map { |inc| [inc.vps.class.name, inc.vps_id] })

      use_chain(IncidentReport::Send, args: [
                  VpsAdmin::API::IncidentReports::Result.new(incidents:)
                ])

      now = Time.now

      incidents.each do |incident|
        process_incident(incident)
        incident.update!(reported_at: now)
      end
    end
  end
end
