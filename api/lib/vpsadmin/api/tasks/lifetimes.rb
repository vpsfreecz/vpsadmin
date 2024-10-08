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
    # [REASON_%LANG%]:  Provide custom reason that will be saved in every object's
    #            state log. %LANG% is a language code in upper case.
    # [LIMIT]:   Maximum number of objects to progress at a time.
    # [EXECUTE]: The states are progressed only if EXECUTE is 'yes'. If not,
    #            the task just prints what would happen.
    def progress
      required_env(%w[OBJECTS])

      time = Time.now.utc
      time -= ENV.fetch('GRACE', 0).to_i

      expiration = Time.now.utc + ENV.fetch('NEW_EXPIRATION').to_i if ENV['NEW_EXPIRATION']

      limit = ENV.fetch('LIMIT', 30).to_i
      raise 'invalid limit' if limit <= 0

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
             && (instance.created_at.nil? || instance.created_at < (Time.now - (6 * 30 * 24 * 60 * 60))) \
             && instance.expiration_date > (Time.now - (30 * 24 * 60 * 60)) \
             && instance.object_state == 'active'
            puts '    we still love you'
            next
          end

          next if ENV['EXECUTE'] != 'yes'

          begin
            instance.progress_object_state(
              :enter,
              reason: get_reason(instance),
              expiration:
            )
          rescue ResourceLocked
            puts '    resource locked'
            next
          end
        end
      end
    end

    # Mail users regarging expiring objects.
    #
    # Accepts the following environment variables:
    # [OBJECTS]:    A list of object names to inform about, separated by a comma.
    #               To inform about all objects, use special name 'all'.
    # [STATES]:     A list of states that an object must be in to be included.
    #               If not specified, all states are included.
    # [FROM_DAYS]:  Number of days added or removed from the expiration date. Only
    #               objects with `expiration_date + FROM_DAYS > now` are considered.
    # [FORCE_DAY]:  Selected number of days after/before the expiration date, where
    #               a notification is sent even if remind_after_date is set.
    # [FORCE_ONLY]: Send notification only when `FORCE_DAY` matches.
    # [EXECUTE]:    The notifications are sent only if EXECUTE is 'yes'. If not,
    #               the task just prints what would happen.
    #
    # Examples:
    #   FROM_DAYS=-7 to notify about objects a week before their expiration
    #   FORCE_DAY=-1 to send a forced notification a day before the expiration
    def mail_expiration
      required_env(%w[OBJECTS FROM_DAYS])

      classes = get_objects
      from_days = ENV['FROM_DAYS'].to_i
      force_days = ENV['FORCE_DAY'] ? ENV['FORCE_DAY'].split(',').map(&:to_i) : nil
      force_only = ENV['FORCE_ONLY'] == 'yes'
      states = get_states
      now = Time.now.utc

      classes.each do |cls|
        q = cls
        q = q.where('expiration_date < ?', now - (from_days * 24 * 60 * 60))
        q = q.where(object_state: states) if states

        objects = []

        q.each do |obj|
          puts "#{cls} id=#{obj.id} state=#{obj.object_state} expiration=#{obj.expiration_date} remind_after=#{obj.remind_after_date}"

          if send_notification?(obj, now, force_days, force_only)
            puts '  sending notification'
            objects << obj
          else
            puts '  skip'
          end
        end

        next if objects.none? || ENV['EXECUTE'] != 'yes'

        TransactionChains::Lifetimes::ExpirationWarning.fire(cls, objects)
      end
    end

    protected

    def send_notification?(obj, now, force_days, force_only)
      do_remind = obj.remind_after_date.nil? || obj.remind_after_date < now

      if force_days
        days_diff = (now - obj.expiration_date) / 60 / 60 / 24

        do_force = force_days.detect do |day|
          days_diff >= day && days_diff < day + 1
        end

        if do_force
          puts '  forced'
          true
        elsif !force_only && do_remind
          puts '  remind allowed'
          true
        else
          false
        end

      elsif do_remind
        puts '  remind allowed'
        true
      else
        false
      end
    end

    def get_objects
      return VpsAdmin::API::Lifetimes.models if ENV['OBJECTS'] == 'all'

      classes = []

      ENV.fetch('OBJECTS').split(',').each do |obj|
        cls = Object.const_get(obj)

        raise warn "Unable to find a class for '#{obj}'" unless obj

        classes << cls
      end

      classes
    end

    def get_states
      return unless ENV['STATES']

      ENV.fetch('STATES').split(',').map do |v|
        i = VpsAdmin::API::Lifetimes::STATES.index(v.to_sym)
        next(i) if i

        raise "Invalid object state '#{v}'"
      end
    end

    def get_reason(obj)
      user = get_user(obj)
      return ENV.fetch('REASON', '') if user.nil?

      ENV["REASON_#{user.language.code.upcase}"] || ENV.fetch('REASON', '')
    end

    def get_user(obj)
      if obj.respond_to?(:user)
        obj.user
      elsif obj.is_a?(::User)
        obj
      end
    end
  end
end
