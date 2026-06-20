module TransactionChains
  class User::Resume < ::TransactionChain
    label 'Resume'

    def link_chain(user, target, _state, log)
      event =
        if target
          prepare_event!(
            'user.resumed',
            user:,
            source: log,
            subject: 'User account resumed',
            summary: "User #{user.login} was resumed",
            parameters: {
              state: log.state || 'active',
              reason: log.reason,
              expiration_date: log.expiration_date&.iso8601
            }
          )
        end

      user.vpses.where(object_state: ::Vps.object_states[:active]).each do |vps|
        use_chain(Vps::Start, args: vps)
      end

      user.dns_records.joins(:dns_zone).where(original_enabled: true).each do |r|
        r.enabled = true

        use_chain(DnsZone::UpdateRecord, args: [r])
      end

      user.dns_zones.where(original_enabled: true).each do |dns_zone|
        use_chain(DnsZone::Update, args: [dns_zone, { enabled: true }])
      end

      release_event_deliveries!(event)
    end
  end
end
