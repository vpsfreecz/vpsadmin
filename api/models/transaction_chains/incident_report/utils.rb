module TransactionChains
  module IncidentReport::Utils
    class << self
      def requires_chain?(incident)
        action = incident.vps_action.to_s

        incident.cpu_limit.present? || (action.present? && action != 'none')
      end

      def fire_new(incident)
        if requires_chain?(incident)
          return TransactionChains::IncidentReport::New.fire2(args: [incident])
        end

        ret = VpsAdmin::API::NotificationEvents.run_chain(
          TransactionChains::IncidentReport::New,
          args: [incident]
        )
        [nil, ret]
      end

      def fire_process(incidents)
        direct, chained = Array(incidents).partition { |incident| !requires_chain?(incident) }

        if direct.any?
          VpsAdmin::API::NotificationEvents.run_chain(
            TransactionChains::IncidentReport::Process,
            args: [direct]
          )
        end

        chained.each do |incident|
          TransactionChains::IncidentReport::Process.fire([incident])
        rescue ResourceLocked
          raise unless block_given?

          yield incident
        end
      end

      def fire_send(result, message: nil)
        VpsAdmin::API::NotificationEvents.run_chain(
          TransactionChains::IncidentReport::Send,
          args: [result],
          kwargs: { message: }
        )
      end

      def fire_reply(message, result)
        VpsAdmin::API::NotificationEvents.run_chain(
          TransactionChains::IncidentReport::Reply,
          args: [message, result]
        )
      end
    end

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
