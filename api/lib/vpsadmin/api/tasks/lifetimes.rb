module VpsAdmin::API::Tasks
  class Lifetime < Base
    # Move expired objects to the next state.
    #
    # Accepts the following environment variables:
    # [OBJECTS]: A list of object names to inform about, separated by a comma.
    #            To inform about all objects, use special name 'all'.
    # [STATES]:  A list of states that an object must be in to be included.
    #            If not specified, all states are included.
    # [GRACE]:   A number of seconds added to the expiration date, effectively
    #            postponing the expiration date.
    # [NEW_EXPIRATION]: Objects progressing to another state have expiration
    #                   set to current time + +NEW_EXPIRATION+ number of
    #                   seconds.
    # [REASON]:  Provide custom reason that will be saved in every object's
    #            state log.
    # [LIMIT]:   Maximum number of objects to progress at a time.
    # [EXECUTE]: The states are progressed only if EXECUTE is 'yes'. If not,
    #            the task just prints what would happen.
    def progress
      required_env(%w(OBJECTS))

      time = Time.now.utc
      time -= ENV['GRACE'].to_i if ENV['GRACE']

      expiration = if ENV['NEW_EXPIRATION']
                     Time.now.utc + ENV['NEW_EXPIRATION'].to_i
                   else
                     nil
                   end

      limit = ENV['LIMIT'] ? ENV['LIMIT'].to_i : 30
      fail 'invalid limit' if limit <= 0

      puts "Progressing objects having expiration date older than #{time}"
      states = get_states

      get_objects.each do |obj|
        puts "Model #{obj}"

        q = obj.where('expiration_date < ?', time)
        q = q.where(object_state: states) if states
        q = q.order('full_name DESC') if obj.name == 'Dataset'
        q = q.limit(limit)

        q.each do |instance|
          puts "  id=#{instance.send(obj.primary_key)}"

          # TODO: this is a temporary relaxation of user suspension rules for
          # users that exist for more than six months. They are suspended
          # a month after the expiration date has passed.
          if instance.is_a?(::User) \
             && (instance.created_at.nil? || instance.created_at < (Time.now - 6*30*24*60*60)) \
             && instance.expiration_date > (Time.now - 30*24*60*60) \
             && instance.object_state == 'active'
            puts "    we still love you"
            next
          end

          next if ENV['EXECUTE'] != 'yes'

          begin
            instance.progress_object_state(
              :enter,
              reason: ENV['REASON'],
              expiration: expiration
            )

          rescue ResourceLocked
            puts "    resource locked"
            next
          end
        end
      end
    end

    # Mail users regarging expiring objects.
    #
    # Accepts the following environment variables:
    # [OBJECTS]:   A list of object names to inform about, separated by a comma.
    #              To inform about all objects, use special name 'all'.
    # [STATES]:    A list of states that an object must be in to be included.
    #              If not specified, all states are included.
    # [FROM_DAYS]: Number of days added or removed from the expiration date. Only
    #              objects with `expiration_date + FROM_DAYS > now` are considered.
    # [FORCE_DAY]: Selected number of days after/before the expiration date, where
    #              a notification is sent even if remind_after_date is set.
    #
    # Examples:
    #   FROM_DAYS=-7 to notify about objects a week before their expiration
    #   FORCE_DAY=-1 to send a forced notification a day before the expiration
    def mail_expiration
      required_env(%w(OBJECTS FROM_DAYS))

      classes = get_objects
      from_days = ENV['FROM_DAYS'].to_i
      force_days = ENV['FORCE_DAY'] ? ENV['FORCE_DAY'].split(',').map(&:to_i) : nil
      states = get_states
      now = Time.now.utc

      classes.each do |cls|
        q = cls
        q = q.where('expiration_date < ?', now - from_days * 24 * 60 * 60)
        q = q.where(object_state: states) if states

        objects = []

        q.each do |obj|
          objects << obj if send_notification?(obj, now, force_days)
        end

        next unless objects.any?

        TransactionChains::Lifetimes::ExpirationWarning.fire(cls, objects)
      end
    end

    protected
    def send_notification?(obj, now, force_days)
      do_remind = obj.remind_after_date.nil? || obj.remind_after_date < now

      if force_days
        days_diff = (now - obj.expiration_date) / 60 / 60 / 24

        do_force = force_days.detect do |day|
          days_diff >= day && days_diff < day+1
        end

        return true if do_force || do_remind

      elsif do_remind
        return true
      else
        return false
      end
    end

    def get_objects
      return VpsAdmin::API::Lifetimes.models if ENV['OBJECTS'] == 'all'

      classes = []

      ENV['OBJECTS'].split(',').each do |obj|
        cls = Object.const_get(obj)

        fail warn "Unable to find a class for '#{obj}'" unless obj

        classes << cls
      end

      classes
    end

    def get_states
      return unless ENV['STATES']

      ENV['STATES'].split(',').map do |v|
        i = VpsAdmin::API::Lifetimes::STATES.index(v.to_sym)
        next(i) if i

        fail "Invalid object state '#{v}'"
      end
    end
  end
end
