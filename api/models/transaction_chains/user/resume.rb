module TransactionChains
  class User::Resume < ::TransactionChain
    label 'Resume'

    def link_chain(user, target, _state, log)
      if target
        mail(:user_resume, {
               user:,
               vars: {
                 user:,
                 state: log
               }
             })
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
    end
  end
end
