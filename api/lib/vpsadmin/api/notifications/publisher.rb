module VpsAdmin::API::Notifications
  class Publisher
    class << self
      def default
        @default ||= new
      end
    end

    def initialize(config: Config.load)
      @config = config
      @connection = nil
    end

    def publish_after_commit(deliveries)
      deliveries = Array(deliveries).select do |delivery|
        DeliveryActions.known?(delivery.action) && delivery.released_state?
      end
      return if deliveries.empty?

      if ActiveRecord.respond_to?(:after_all_transactions_commit)
        ActiveRecord.after_all_transactions_commit { publish(deliveries) }
      else
        publish(deliveries)
      end
    end

    def publish(deliveries)
      return unless rabbitmq_configured?

      channel = connection.create_channel
      exchange = channel.direct(EXCHANGE_NAME, durable: true)

      grouped, direct = deliveries.partition do |delivery|
        delivery.grouping_enabled? && delivery.event_delivery_group_id.nil?
      end

      direct.group_by(&:action).each_key do |action|
        declare_queue(channel, exchange, action)
      end
      declare_grouping_queue(channel, exchange) if grouped.any?

      direct.each do |delivery|
        exchange.publish(
          JSON.dump({
                      delivery_id: delivery.id,
                      action: delivery.action,
                      released_at: delivery.released_at&.iso8601
                    }),
          routing_key: DeliveryActions.routing_key(delivery.action),
          persistent: true
        )
      end
      grouped.uniq { |delivery| [delivery.event_id, delivery.group_key] }.each do |delivery|
        exchange.publish(
          JSON.dump({
                      event_id: delivery.event_id,
                      group_key: delivery.group_key,
                      released_at: delivery.released_at&.iso8601
                    }),
          routing_key: GROUPING_ROUTING_KEY,
          persistent: true
        )
      end
    rescue StandardError => e
      warn "Unable to notify event delivery dispatchers: #{e.class}: #{e.message}"
    ensure
      channel.close if channel && channel.respond_to?(:open?) && channel.open?
    end

    protected

    def declare_queue(channel, exchange, action)
      queue = channel.queue(
        DeliveryActions.queue_name(action),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )
      queue.bind(exchange, routing_key: DeliveryActions.routing_key(action))
    end

    def declare_grouping_queue(channel, exchange)
      queue = channel.queue(
        GROUPING_QUEUE,
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )
      queue.bind(exchange, routing_key: GROUPING_ROUTING_KEY)
    end

    def connection
      if @connection.nil? || !@connection.open?
        rabbitmq = rabbitmq_config
        @connection = Bunny.new(
          hosts: Array(rabbitmq.fetch('hosts')),
          vhost: rabbitmq.fetch('vhost', '/'),
          username: rabbitmq.fetch('username'),
          password: rabbitmq.fetch('password'),
          log_file: $stderr
        )
        @connection.start
      end

      @connection
    end

    def rabbitmq_configured?
      rabbitmq_config
      true
    rescue KeyError
      false
    end

    def rabbitmq_config
      rabbitmq = @config.fetch('rabbitmq')
      rabbitmq.fetch('hosts')
      rabbitmq.fetch('username')
      rabbitmq.fetch('password')
      rabbitmq
    end
  end

  class Release
    class << self
      def release!(deliveries, publisher: Publisher.default)
        ids = Array(deliveries)
              .map { |delivery| delivery.respond_to?(:id) ? delivery.id : delivery }
              .map(&:to_i)
              .uniq
        return [] if ids.empty?

        now = Time.now
        released = []

        ::EventDelivery.transaction do
          released = ::EventDelivery
                     .where(id: ids, state: 'prepared')
                     .order(:id)
                     .to_a
          next if released.empty?

          ::EventDelivery.where(id: released.map(&:id)).update_all(
            state: ::EventDelivery.states.fetch('released'),
            released_at: now,
            next_attempt_at: now,
            updated_at: now
          )

          released.each do |delivery|
            delivery.state = 'released'
            delivery.released_at = now
            delivery.next_attempt_at = now
          end
        end

        publisher.publish_after_commit(released)
        released
      end
    end
  end
end
