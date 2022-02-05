module TransactionChains
  class Lifetimes::ExpirationWarning < ::TransactionChain
    label 'Expiration'
    allow_empty

    def link_chain(klass, objects)
      base_url = ::SysConfig.get(:webui, :base_url)
      now = Time.now.utc

      objects.each do |obj|
        user =
          if obj.is_a?(::User)
            obj
          elsif obj.respond_to?(:user)
            obj.user
          else
            fail "Unable to find an owner for #{obj} of class #{klass}"
          end

        days_before = (obj.expiration_date - now) / 60 / 60 / 24
        days_after = (now - obj.expiration_date) / 60 / 60 / 24

        mail(:expiration_warning, {
          params: {
            object: klass.name.underscore,
            state: obj.object_state,
          },
          user: user,
          vars: {
            base_url: base_url,
            object: obj,
            state: obj.current_object_state,
            expires_in_days: days_before,
            expired_days_ago: days_after,
            expires_in_a_day: days_before >= 0 && days_before <= 1.5,
            klass.name.underscore => obj,
          }
        }) if user.mailer_enabled
      end
    end
  end
end
