module TransactionChains
  class User::Suspend < ::TransactionChain
    label 'Suspend'

    def link_chain(user, target, _state, log)
      if target
        mail(:user_suspend, {
               user:,
               vars: {
                 user:,
                 state: log
               }
             })
      end

      user.vpses.where(object_state: [
                         ::Vps.object_states[:active],
                         ::Vps.object_states[:suspended]
                       ]).each do |vps|
        use_chain(Vps::Stop, args: vps)
      end

      return unless target

      user.dns_zones.each do |dns_zone|
        use_chain(DnsZone::Update, args: [
                    dns_zone,
                    { enabled: false, original_enabled: dns_zone.enabled }
                  ])
      end

      user.dns_records.joins(:dns_zone).each do |r|
        r.original_enabled = r.enabled
        r.enabled = false

        use_chain(DnsZone::UpdateRecord, args: [r])
      end
    end
  end
end
