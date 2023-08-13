module TransactionChains
  class IncidentReport::Send < ::TransactionChain
    label 'Incident report'
    allow_empty

    # @param result [VpsAdmin::API::IncidentReports::Result]
    # @param message [Mail::Message, nil]
    def link_chain(result, message: nil)
      concerns(:affect, *(result.active.map { |v| [v.vps.class.name, v.vps_id] }.uniq))

      if message && result.reply
        use_chain(IncidentReport::Reply, args: [message, result])
      end

      result.active.each do |inc|
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
