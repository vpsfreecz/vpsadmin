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

      user.dns_zones.each do |dns_zone|
        use_chain(DnsZone::Update, args: [dns_zone, { enabled: true }])
      end
    end
  end
end
