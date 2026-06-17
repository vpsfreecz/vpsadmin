module TransactionChains
  class Lifetimes::ExpirationWarning < ::TransactionChain
    label 'Expiration'
    allow_empty

    def link_chain(klass, objects)
      base_url = ::SysConfig.get(:webui, :base_url)
      now = Time.now.utc
      object_name = klass.name.underscore

      objects.each do |obj|
        user =
          if obj.is_a?(::User)
            obj
          elsif obj.respond_to?(:user)
            obj.user
          else
            raise "Unable to find an owner for #{obj} of class #{klass}"
          end

        days_before = (obj.expiration_date - now) / 60 / 60 / 24
        days_after = (now - obj.expiration_date) / 60 / 60 / 24
        state = obj.current_object_state

        route_event!(
          'lifetime.expiration_warning',
          user:,
          vps: obj.is_a?(::Vps) ? obj : nil,
          source: obj,
          subject: "#{klass.name} #{object_label(obj)} expiration warning"[0, 255],
          summary: expiration_summary(obj, days_before, days_after),
          parameters: event_parameters(obj, object_name, days_before, days_after),
          email_vars: {
            base_url:,
            user:,
            object: obj,
            state:,
            expires_in_days: days_before,
            expired_days_ago: days_after,
            expires_in_a_day: days_before.between?(0, 1.5),
            object_name => obj
          }
        )
      end
    end

    protected

    def event_parameters(obj, object_name, days_before, days_after)
      {
        object: object_name,
        object_id: obj.id,
        object_label: object_label(obj),
        state: obj.object_state,
        expiration_date: obj.expiration_date&.iso8601,
        remind_after_date: obj.remind_after_date&.iso8601,
        expires_in_days: days_before,
        expired_days_ago: days_after,
        expires_in_a_day: days_before.between?(0, 1.5)
      }
    end

    def object_label(obj)
      if obj.respond_to?(:hostname)
        obj.hostname
      elsif obj.respond_to?(:login)
        obj.login
      elsif obj.respond_to?(:label)
        obj.label
      else
        "##{obj.id}"
      end
    end

    def expiration_summary(obj, days_before, days_after)
      label = object_label(obj)

      if days_before.between?(0, 1.5)
        "#{label} expires in less than one day"
      elsif days_before >= 0
        "#{label} expires in approximately #{days_before.ceil} days"
      else
        "#{label} expired approximately #{days_after.ceil} days ago"
      end
    end
  end
end
