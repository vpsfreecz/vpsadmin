module TransactionChains
  class User::Revive < ::TransactionChain
    label 'Revive'

    def link_chain(user, _target, _state, log)
      route_event!(
        'user.revived',
        user:,
        source: log,
        subject: 'User account restored',
        summary: "User #{user.login} was restored",
        parameters: {
          state: log.state || 'active',
          reason: log.reason,
          expiration_date: log.expiration_date&.iso8601
        },
        email_vars: {
          user:,
          state: log
        }
      )

      user.exports.where(original_enabled: true).each do |ex|
        use_chain(Export::Update, args: [ex, { enabled: true }])
      end

      user.vpses.where(object_state: ::Vps.object_states[:soft_delete]).each do |vps|
        vps.set_object_state(:active, reason: 'User was revived', chain: self)
      end
    end
  end
end
