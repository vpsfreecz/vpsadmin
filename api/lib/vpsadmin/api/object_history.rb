module VpsAdmin::API
  module ObjectHistory
    module Model
      module ClassMethods
        # Configure a list of valid event types that may be logged for objects
        # of this class.
        def log_events(*events)
          @log_events = events.flatten
        end
      end

      module InstanceMethods
        # @param type [Symbol] event type
        # @param data data specific to event type
        # @return [::ObjectHistory]
        def log_change(type, data = nil, time: nil)
          events = self.class.instance_variable_get('@log_events')
          raise "no event types configured for #{self.class}" unless events
          raise "'#{type}' is not a valid event type" unless events.include?(type)

          session = ::UserSession.current

          ::ObjectHistory.create!(
            user: session && session.user,
            user_session: session,
            tracked_object: self,
            event_type: type,
            event_data: data,
            created_at: time
          )
        end

        alias log log_change
      end

      def self.included(klass)
        klass.send(:extend, ClassMethods)
        klass.send(:include, InstanceMethods)
      end
    end
  end
end
