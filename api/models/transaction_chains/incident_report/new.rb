module TransactionChains
  class IncidentReport::New < ::TransactionChain
    label 'Incident report'

    def link_chain(incident)
      concerns(:affect, [incident.vps.class.name, incident.vps_id])

      use_chain(IncidentReport::Send, args: [
                  VpsAdmin::API::IncidentReports::Result.new(incidents: [incident])
                ])

      return unless incident.cpu_limit

      use_chain(
        Vps::Update,
        args: [
          incident.vps,
          { cpu_limit: }
        ],
        kwargs: { admin: incident.filed_by }
      )
    end
  end
end
