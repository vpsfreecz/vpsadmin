require_relative 'utils'

module TransactionChains
  class IncidentReport::New < ::TransactionChain
    label 'Incident report'

    include IncidentReport::Utils

    def link_chain(incident)
      concerns(:affect, [incident.vps.class.name, incident.vps_id])

      use_chain(IncidentReport::Send, args: [
                  VpsAdmin::API::IncidentReports::Result.new(incidents: [incident])
                ])

      process_incident(incident)
    end
  end
end
