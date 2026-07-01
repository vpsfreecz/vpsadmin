module TransactionChains
  class Vps::Block < ::TransactionChain
    label 'Block'

    def link_chain(vps, target, _state, log)
      use_chain(Vps::Stop, args: vps)

      return unless target

      route_event!(
        'vps.suspended',
        user: vps.user,
        vps:,
        source: log,
        subject: "VPS ##{vps.id} suspended",
        summary: log.reason,
        payload: {
          vps_id: vps.id,
          vps_hostname: vps.hostname,
          state: log.state,
          reason: log.reason,
          expiration_date: log.expiration_date&.iso8601,
          changed_by_id: log.user&.id,
          changed_by_name: log.user&.full_name
        }
      )
    end
  end
end
