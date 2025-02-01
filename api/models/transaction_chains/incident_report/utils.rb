module TransactionChains
  module IncidentReport::Utils
    # @param incident [::IncidentReport]
    def process_incident(incident)
      if incident.cpu_limit
        use_chain(
          Vps::Update,
          args: [
            incident.vps,
            { cpu_limit: incident.cpu_limit }
          ],
          kwargs: { admin: incident.filed_by }
        )
      end

      case incident.vps_action
      when 'stop'
        use_chain(Vps::Stop, args: [incident.vps])
      when 'suspend'
        incident.vps.set_object_state(
          :suspended,
          reason: "Incident report ##{incident.id}: #{incident.subject}",
          chain: self
        )
      when 'disable_network'
        use_chain(
          Vps::EnableNetwork,
          args: [incident.vps, false],
          kwargs: { reason: "Incident report ##{incident.id}: #{incident.subject}" }
        )
      end
    end
  end
end
