module TransactionChains
  class User::SoftDelete < ::TransactionChain
    label 'Soft delete'

    def link_chain(user, target, _state, log)
      mail(:user_soft_delete, {
             user:,
             vars: {
               user:,
               state: log
             }
           })

      if target
        user.vpses.where(object_state: [
                           ::Vps.object_states[:active],
                           ::Vps.object_states[:suspended]
                         ]).each do |vps|
          vps.set_object_state(
            :soft_delete,
            reason: 'User was soft deleted',
            chain: self
          )
        end

        user.exports.each do |ex|
          use_chain(Export::Update, args: [ex, { enabled: false, original_enabled: ex.enabled }])
        end

        user.dns_zones.each do |dns_zone|
          use_chain(DnsZone::Update, args: [dns_zone, { enabled: false, original_enabled: dns_zone.enabled }])
        end

        user.dns_records.joins(:dns_zone).each do |r|
          r.original_enabled = r.enabled
          r.enabled = false

          use_chain(DnsZone::UpdateRecord, args: [r])
        end
      end

      user.user_sessions.where.not(token: nil).each(&:close!)

      user.single_sign_ons.destroy_all
      user.oauth2_authorizations.destroy_all
      user.metrics_access_tokens.destroy_all
    end
  end
end
