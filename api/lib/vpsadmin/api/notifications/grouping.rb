module VpsAdmin::API::Notifications
  class GroupActivation
    class << self
      def activate_released!(limit: DEFAULT_LIMIT)
        released_groups = ::EventDelivery
                          .where(state: 'released', event_delivery_group_id: nil)
                          .where.not(group_key: nil)
                          .select(:event_id, :group_key)
                          .distinct
                          .order(:event_id, :group_key)
                          .limit(limit)
                          .pluck(:event_id, :group_key)

        released_groups.each do |event_id, group_key|
          activate_event!(event_id, group_key)
        end
      end

      def activate!(delivery, now: Time.now)
        return delivery.event_delivery_group if delivery.event_delivery_group
        return unless delivery.grouping_enabled?

        activate_event!(delivery.event_id, delivery.group_key, now:)
      end

      def activate_event!(event_id, group_key, now: Time.now)
        group = nil

        ::EventDelivery.transaction do
          lock_transaction_chains!(transaction_chain_ids_for(event_id, group_key))

          delivery = released_scope(event_id, group_key).lock.first
          next unless delivery

          group = find_or_create_group!(delivery)

          group.with_lock do
            deliveries = released_scope(event_id, group_key).lock.to_a
            next if deliveries.empty?

            first_member_at = deliveries.filter_map(&:released_at).min || now
            next_flush_at =
              group.next_flush_at ||
              [
                first_member_at + delivery.group_wait_seconds,
                group.last_sealed_at &&
                  (group.last_sealed_at + delivery.group_interval_seconds)
              ].compact.max

            group.update!(next_flush_at:)
            ::EventDelivery.where(id: deliveries.map(&:id)).update_all(
              event_delivery_group_id: group.id,
              state: ::EventDelivery.states.fetch('grouping'),
              next_attempt_at: nil,
              updated_at: now
            )
          end
        end

        group
      end

      protected

      def released_scope(event_id, group_key)
        ::EventDelivery
          .where(
            event_id:,
            group_key:,
            state: 'released',
            event_delivery_group_id: nil
          )
          .order(:id)
      end

      def transaction_chain_ids_for(event_id, group_key)
        transaction_ids = released_scope(event_id, group_key)
                          .where.not(transaction_id: nil)
                          .distinct
                          .pluck(:transaction_id)
        ::Transaction
          .where(id: transaction_ids)
          .where.not(transaction_chain_id: nil)
          .distinct
          .order(:transaction_chain_id)
          .pluck(:transaction_chain_id)
      end

      def lock_transaction_chains!(chain_ids)
        chain_ids.each do |chain_id|
          ::TransactionChain.where(id: chain_id).lock.take
        end
      end

      def find_or_create_group!(delivery)
        ::EventDeliveryGroup.find_or_create_by!(group_key: delivery.group_key) do |group|
          group.event_route = delivery.event_route
          group.route_owner = delivery.event_routing_context&.recipient_user
          group.notification_receiver = delivery.notification_receiver
          group.notification_receiver_label = delivery.notification_receiver&.label
          group.labels = delivery.group_labels || {}
          group.group_wait_seconds = delivery.group_wait_seconds
          group.group_interval_seconds = delivery.group_interval_seconds
        end
      rescue ActiveRecord::RecordNotUnique
        retry
      end
    end
  end

  class GroupSealer
    class << self
      def seal_due!(limit: DEFAULT_LIMIT, now: Time.now, publisher: Publisher.default)
        groups = ::EventDeliveryGroup
                 .due(now)
                 .order(:next_flush_at, :id)
                 .limit(limit)
                 .to_a

        groups.flat_map do |group|
          seal!(group, now:, publisher:)
        end
      end

      def seal!(group, now: Time.now, publisher: Publisher.default)
        released = []

        ::EventDeliveryGroup.transaction do
          lock_transaction_chains!(transaction_chain_ids_for(group))
          group.lock!
          group.reload
          next if group.next_flush_at.nil? || group.next_flush_at > now

          members = group.event_deliveries
                         .where(state: 'grouping')
                         .order(:id)
                         .lock
                         .to_a
          if members.empty?
            group.update!(next_flush_at: nil)
            next
          end

          streams = members.group_by(&:group_stream_key)
          if streams.has_key?(nil)
            raise "notification group ##{group.id} has a delivery without a stream key"
          end

          event_sets = streams.values.map { |stream| stream.map(&:event_id).sort }.uniq
          if event_sets.length != 1
            raise "notification group ##{group.id} has inconsistent stream membership"
          end

          streams.each_value do |stream|
            leader = stream.first
            member_ids = stream.drop(1).map(&:id)
            if member_ids.any?
              ::EventDelivery.where(id: member_ids, state: 'grouping').update_all(
                state: ::EventDelivery.states.fetch('grouped'),
                effective_event_delivery_id: leader.id,
                next_attempt_at: nil,
                updated_at: now
              )
            end

            leader.update!(
              state: 'released',
              effective_event_delivery_id: nil,
              released_at: now,
              next_attempt_at: now
            )
            released << leader
          end

          group.update!(
            last_sealed_at: now,
            next_flush_at: nil
          )
        end

        publisher.publish_after_commit(released)
        released
      end

      protected

      def transaction_chain_ids_for(group)
        transaction_ids = group.event_deliveries
                               .where(state: 'grouping')
                               .where.not(transaction_id: nil)
                               .distinct
                               .pluck(:transaction_id)
        ::Transaction
          .where(id: transaction_ids)
          .where.not(transaction_chain_id: nil)
          .distinct
          .order(:transaction_chain_id)
          .pluck(:transaction_chain_id)
      end

      def lock_transaction_chains!(chain_ids)
        chain_ids.each do |chain_id|
          ::TransactionChain.where(id: chain_id).lock.take
        end
      end
    end
  end

  class Grouper
    def self.run
      new.run
    end

    def initialize(config: Config.load, sleeper: ->(seconds) { sleep(seconds) })
      @config = config
      @sleeper = sleeper
      @running = true
      @connection = nil
    end

    def run
      trap_signals

      if rabbitmq_configured?
        run_with_rabbitmq
      else
        run_reconciliation_loop
      end
    end

    def dispatch_due(limit: DEFAULT_LIMIT)
      ActiveRecord::Base.connection_pool.with_connection do
        GroupActivation.activate_released!(limit:)
        GroupSealer.seal_due!(limit:)
      end
    end

    def dispatch_group(event_id, group_key)
      ActiveRecord::Base.connection_pool.with_connection do
        group = GroupActivation.activate_event!(event_id, group_key)
        GroupSealer.seal!(group) if group&.next_flush_at && group.next_flush_at <= Time.now
      end
    end

    protected

    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { @running = false }
      end
    end

    def run_with_rabbitmq
      channel = connection.create_channel
      exchange = channel.direct(EXCHANGE_NAME, durable: true)
      queue = channel.queue(
        GROUPING_QUEUE,
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )
      queue.bind(exchange, routing_key: GROUPING_ROUTING_KEY)

      while @running
        dispatch_due

        delivery_info, _properties, payload = queue.pop(manual_ack: true)
        if delivery_info
          handle_queue_payload(channel, delivery_info, payload)
        else
          @sleeper.call(poll_interval)
        end
      end
    ensure
      channel.close if channel && channel.respond_to?(:open?) && channel.open?
      @connection.close if @connection&.open?
    end

    def handle_queue_payload(channel, delivery_info, payload)
      data = JSON.parse(payload)
      dispatch_group(data.fetch('event_id'), data.fetch('group_key'))
      channel.ack(delivery_info.delivery_tag)
    rescue StandardError => e
      warn "Unable to process notification grouping message: #{e.class}: #{e.message}"
      channel.nack(delivery_info.delivery_tag, false, true)
    end

    def run_reconciliation_loop
      while @running
        dispatch_due
        @sleeper.call(poll_interval)
      end
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

    def poll_interval
      [@config.fetch('poll_interval', DEFAULT_POLL_INTERVAL).to_f, 0.1].max
    end
  end
end
