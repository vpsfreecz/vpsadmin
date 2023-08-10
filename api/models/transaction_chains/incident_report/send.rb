module TransactionChains
  class IncidentReport::Send < ::TransactionChain
    label 'Incident report'

    def link_chain(incidents)
      concerns(:affect, *(incidents.map { |v| [v.vps.class.name, v.vps_id] }.uniq))

      incidents.each do |inc|
        mail(:vps_incident_report, {
          user: inc.user,
          vars: {
            base_url: ::SysConfig.get(:webui, :base_url),
            user: inc.user,
            vps: inc.vps,
            incident: inc,
          },
        })
      end
    end
  end
end
