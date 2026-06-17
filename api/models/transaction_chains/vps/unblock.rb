module TransactionChains
  class Vps::Unblock < ::TransactionChain
    label 'Unblock'

    def link_chain(vps, target, _state, log)
      use_chain(Vps::Start, args: vps)

      return unless target

      route_event!(
        'vps.resumed',
        user: vps.user,
        vps:,
        source: log,
        subject: "VPS ##{vps.id} resumed",
        summary: log.reason,
        parameters: {
          vps_id: vps.id,
          vps_hostname: vps.hostname,
          state: log.state,
          reason: log.reason,
          expiration_date: log.expiration_date&.iso8601,
          changed_by_id: log.user&.id,
          changed_by_name: log.user&.full_name
        },
        email_vars: {
          vps:,
          state: log
        }
      )
    end
  end
end
