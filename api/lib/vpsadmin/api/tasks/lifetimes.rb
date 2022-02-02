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

      puts "Progressing objects having expiration date older than #{time}"
      states = get_states

      get_objects.each do |obj|
        puts "Model #{obj}"

        q = obj.where('expiration_date < ?', time)
        q = q.where(object_state: states) if states
        q = q.order('full_name DESC') if obj.name == 'Dataset'

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
    # [OBJECTS]: A list of object names to inform about, separated by a comma.
    #            To inform about all objects, use special name 'all'.
    # [STATES]:  A list of states that an object must be in to be included.
    #            If not specified, all states are included.
    # [DAYS]:    Inform only about objects that will reach expiration in +DAYS+
    #            number of days.
    def mail_expiration
      required_env(%w(OBJECTS DAYS))

      classes = get_objects
      days = ENV['DAYS'].to_i
      states = get_states
      now = Time.now.utc
      time = now + days * 24 * 60 * 60

      classes.each do |cls|
        q = cls.where('expiration_date < ?', time)
        q = q.where('remind_after_date IS NULL OR remind_after_date < ?', now)
        q = q.where(object_state: states) if states

        TransactionChains::Lifetimes::ExpirationWarning.fire(cls, q)
      end
    end

    protected
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
