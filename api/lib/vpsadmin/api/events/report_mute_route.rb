module VpsAdmin::API::Events
  class ReportMuteRoute
    class Error < StandardError; end

    def initialize(current_user:, source_user:, owner:, event_type:, label:, matchers:, expires_at:)
      @current_user = current_user
      @source_user = source_user
      @owner = owner || current_user
      @event_type = event_type
      @label = label
      @matchers = matchers
      @expires_at = expires_at
    end

    def create!
      validate!

      ::EventRoute.transaction do
        owner.lock!

        if owner.event_routes.active.count >= ::EventRoute::MAX_ROUTES
          raise Error, 'route limit reached, refusing to add another one'
        end

        receiver = ::NotificationReceiver.ensure_default_mute_receiver_for!(owner)
        route = owner.event_routes.create!(
          notification_receiver: receiver,
          label:,
          position: ::EventRoute.prepend_position_for(owner),
          enabled: true,
          event_type:,
          subject_scope: owner == source_user ? 'self' : 'visible',
          grouping_enabled: false,
          continue: false,
          expires_at:
        )

        matchers.each do |matcher|
          route.event_route_matchers.create!(
            field: matcher.fetch(:field),
            operator: '==',
            value: matcher.fetch(:value)
          )
        end

        route
      end
    end

    protected

    attr_reader :current_user, :source_user, :owner, :event_type, :label,
                :matchers, :expires_at

    def validate!
      validate_owner!
      raise Error, 'select at least one matcher' if matchers.empty?

      missing = matchers.find { |matcher| matcher.fetch(:value).blank? }
      if missing
        raise Error, "selected matcher #{missing.fetch(:field)} is unavailable"
      end

      return unless expires_at && expires_at <= Time.current

      raise Error, 'expiration time has to be in the future'
    end

    def validate_owner!
      if current_user.role != :admin && (owner != current_user || source_user != current_user)
        raise Error, 'access denied'
      end

      return if owner == source_user
      return if current_user.role == :admin && owner.role == :admin

      raise Error, 'route owner has to be the report account or an administrator'
    end
  end
end
