module TransactionChains
  class IncidentReport::New < ::TransactionChain
    label 'Incident report'

    def link_chain(incident, cpu_limit: nil)
      concerns(:affect, [incident.vps.class.name, incident.vps_id])

      use_chain(IncidentReport::Send, args: [
        VpsAdmin::API::IncidentReports::Result.new(incidents: [incident]),
      ])

      if cpu_limit
        use_chain(Vps::Update, args: [incident.vps, {
          cpu_limit: cpu_limit,
          change_reason: "Incident report ##{incident.id}",
        }])
      end
    end
  end
end
