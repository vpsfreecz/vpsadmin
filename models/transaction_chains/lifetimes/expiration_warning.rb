module TransactionChains
  class Lifetimes::ExpirationWarning < ::TransactionChain
    label 'Expiration'
    allow_empty

    def link_chain(klass, q)
      q.each do |obj|
        user = if obj.is_a?(::User)
                 obj
               elsif obj.respond_to?(:user)
                 obj.user
               else
                 fail "Unable to find an owner for #{obj} of class #{klass}"
               end

        mail(:"expiration_#{klass.name.underscore}_#{obj.object_state}", {
            user: user,
            vars: {
                object: obj,
                state: obj.current_state,
                klass.name.underscore => obj
            }
        }) if user.mailer_enabled
      end
    end
  end
end
