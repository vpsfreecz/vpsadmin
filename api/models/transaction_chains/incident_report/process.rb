module TransactionChains
  class IncidentReport::Process < ::TransactionChain
    label 'Incident report'

    def link_chain(incidents)
      concerns(:affect, *incidents.map { |inc| [inc.vps.class.name, inc.vps_id] })

      use_chain(IncidentReport::Send, args: [
        VpsAdmin::API::IncidentReports::Result.new(incidents: incidents),
      ])

      now = Time.now

      incidents.each do |incident|
        if incident.cpu_limit
          use_chain(Vps::Update, args: [incident.vps, {
            cpu_limit: incident.cpu_limit,
            change_reason: "Incident report ##{incident.id}",
          }])
        end

        incident.update!(reported_at: now)
      end
    end
  end
end
