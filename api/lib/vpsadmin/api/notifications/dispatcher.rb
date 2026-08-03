module VpsAdmin::API::Notifications
  class Dispatcher
    STOP_WORKER = Object.new.freeze

    def self.run(action)
      new(action).run
    end

    def self.dispatch_due(action, **)
      new(action).dispatch_due(**)
    end

    def initialize(
      action,
      config: Config.load,
      monotonic_clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) },
      sleeper: ->(seconds) { sleep(seconds) }
    )
      @action = action.to_s
      unless DeliveryActions.known?(@action)
        raise ArgumentError, "unsupported notification action #{@action}"
      end

      @config = config
      @monotonic_clock = monotonic_clock
      @sleeper = sleeper
      @delivery_action = DeliveryActions.build(
        @action,
        config:,
        monotonic_clock:,
        sleeper:
      )
      @running = true
      @long_running = false
      @delivery_queue = Queue.new
      @delayed_delivery_ids = []
      @queued_delivery_ids = Set.new
      @pool_mutex = Mutex.new
      @pool_condition = ConditionVariable.new
      @delayed_condition = ConditionVariable.new
      @in_flight = 0
      @workers = nil
      @delayed_scheduler = nil
      @stopping_workers = false
    end

    def run
      trap_signals
      @long_running = true
      start_workers unless inline_delivery_dispatch?

      if rabbitmq_configured?
        run_with_rabbitmq
      else
        run_reconciliation_loop
      end
    ensure
      stop_workers
    end

    def dispatch_due(limit: limit_value, wait: true)
      requested_limit = limit.to_i
      delivery_limit = available_delivery_limit(requested_limit)
      return if delivery_limit <= 0

      deliveries = ActiveRecord::Base.connection_pool.with_connection do
        due_deliveries(delivery_limit, scan_limit: requested_limit)
      end

      if inline_delivery_dispatch?
        worker_state = {}
        deliveries.each { |delivery| dispatch_delivery(delivery, worker_state:) }
        return
      end

      deliveries.each { |delivery| submit_delivery_id(delivery.id) }
      wait_for_idle if wait
    ensure
      stop_workers if wait && !@long_running
    end

    def dispatch_delivery_id(id, worker_state: nil, defer_throttles: false)
      return if id.blank?

      delivery = find_delivery(id)
      return unless delivery && delivery.action == @action

      return if delivery.grouping_state? || delivery.grouped_state?

      dispatch_delivery(delivery, worker_state:, defer_throttles:)
    end

    protected

    def due_deliveries(limit, scan_limit: limit)
      @delivery_action.select_due_deliveries(
        limit:,
        scan_limit:,
        due_scope: method(:due_delivery_scope)
      )
    end

    def due_delivery_scope
      scope = ::EventDelivery
              .includes(
                :event,
                :mail_log,
                :event_route,
                :notification_receiver,
                :notification_target,
                :notification_receiver_action
              )
              .where(action: @action, state: %w[released sending])
              .where('group_key IS NULL OR event_delivery_group_id IS NOT NULL')
              .due
              .order(:id)

      excluded_ids = queued_delivery_ids
      excluded_ids.empty? ? scope : scope.where.not(id: excluded_ids)
    end

    def queued_delivery_ids
      @pool_mutex.synchronize { @queued_delivery_ids.to_a }
    end

    def available_delivery_limit(requested_limit)
      limit = requested_limit.to_i
      return limit if inline_delivery_dispatch?

      @pool_mutex.synchronize do
        [limit, max_in_flight - @in_flight].min
      end
    end

    def max_in_flight
      limit_value
    end

    def find_delivery(id)
      ::EventDelivery
        .includes(
          :event,
          :mail_log,
          :event_route,
          :notification_receiver,
          :notification_target,
          :notification_receiver_action
        )
        .find_by(id:)
    end

    def run_with_rabbitmq
      channel = connection.create_channel
      exchange = channel.direct(EXCHANGE_NAME, durable: true)
      queue = channel.queue(
        DeliveryActions.queue_name(@action),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )
      queue.bind(exchange, routing_key: DeliveryActions.routing_key(@action))

      while @running
        dispatch_due(wait: false)

        delivery_info, _properties, payload = queue.pop(manual_ack: true)

        if delivery_info
          handle_queue_payload(channel, delivery_info, payload)
        else
          sleep poll_interval
        end
      end
    ensure
      channel.close if channel && channel.respond_to?(:open?) && channel.open?
    end

    def handle_queue_payload(channel, delivery_info, payload)
      data = JSON.parse(payload)
      if inline_delivery_dispatch?
        ActiveRecord::Base.connection_pool.with_connection do
          dispatch_delivery_id(data['delivery_id'], defer_throttles: false)
        end
      else
        submit_delivery_id(data['delivery_id'])
      end
      channel.ack(delivery_info.delivery_tag)
    rescue StandardError => e
      warn "Unable to process notification delivery message: #{e.class}: #{e.message}"
      channel.nack(delivery_info.delivery_tag, false, true)
    end

    def run_reconciliation_loop
      while @running
        dispatch_due
        sleep poll_interval
      end
    end

    def dispatch_delivery(delivery, worker_state: nil, defer_throttles: false)
      if defer_throttles
        delay = @delivery_action.throttle_delay(delivery, worker_state)
        return delay if delay
      else
        wait_for_delivery_throttles!(delivery, worker_state)
      end

      attempt = claim_delivery(delivery)
      return unless attempt

      delivery.reload
      prepare_grouped_delivery!(delivery)
      result = validate_delivery_result!(deliver(delivery.reload))
      if result.accepted?
        mark_accepted!(delivery, attempt, result)
      else
        mark_success!(delivery, attempt, result)
      end
      nil
    rescue DeliveryPreparationTerminalError => e
      mark_preparation_terminal!(delivery, attempt, e)
      nil
    rescue DeliveryFailure => e
      mark_failure!(
        delivery,
        attempt,
        response_status: e.response_status,
        response_body: e.response_body,
        response_headers: e.response_headers,
        error_summary: e.message
      )
      nil
    rescue StandardError => e
      mark_failure!(
        delivery,
        attempt,
        response_status: exception_response_status(e),
        response_body: exception_response_body(e),
        error_summary: "#{e.class}: #{e.message}"
      )
      nil
    end

    def submit_delivery_id(id)
      return false if id.blank?

      delivery_id = id.to_i
      return false if delivery_id <= 0

      start_workers
      return false unless reserve_delivery_id(delivery_id)

      @delivery_queue << delivery_id
      true
    rescue StandardError
      release_delivery_id(delivery_id) if delivery_id
      raise
    end

    def reserve_delivery_id(delivery_id)
      @pool_mutex.synchronize do
        return false if @queued_delivery_ids.include?(delivery_id)
        return false if @in_flight >= max_in_flight

        @queued_delivery_ids.add(delivery_id)
        @in_flight += 1
        true
      end
    end

    def release_delivery_id(delivery_id)
      @pool_mutex.synchronize do
        @queued_delivery_ids.delete(delivery_id)
        @in_flight -= 1 if @in_flight > 0
        @pool_condition.broadcast if @in_flight == 0
      end
    end

    def start_workers
      @pool_mutex.synchronize do
        return if @workers

        @stopping_workers = false
        @delayed_scheduler = Thread.new { delayed_scheduler_loop }
        @workers = Array.new(concurrency) do |index|
          Thread.new { worker_loop(index + 1) }
        end
      end
    end

    def stop_workers
      workers, delayed_scheduler = @pool_mutex.synchronize do
        ret_workers = @workers
        ret_scheduler = @delayed_scheduler
        @workers = nil
        @delayed_scheduler = nil
        @stopping_workers = true
        @delayed_condition.broadcast
        [ret_workers, ret_scheduler]
      end

      delayed_scheduler&.join

      if workers
        workers.length.times { @delivery_queue << STOP_WORKER }
        workers.each(&:join)
      end
      nil
    end

    def wait_for_idle
      @pool_mutex.synchronize do
        @pool_condition.wait(@pool_mutex) while @in_flight > 0
      end
    end

    def worker_loop(index)
      worker_state = { index: }

      loop do
        delivery_id = @delivery_queue.pop
        break if delivery_id.equal?(STOP_WORKER)

        delay = nil
        begin
          ActiveRecord::Base.connection_pool.with_connection do
            delay = dispatch_delivery_id(
              delivery_id,
              worker_state:,
              defer_throttles: true
            )
          end
        rescue StandardError => e
          warn "Unable to process notification delivery #{delivery_id}: #{e.class}: #{e.message}"
        ensure
          if delay.is_a?(Numeric) && delay > 0
            defer_delivery_id(delivery_id, delay)
          else
            release_delivery_id(delivery_id)
          end
        end
      end
    end

    def defer_delivery_id(delivery_id, delay)
      ready_at = monotonic_time + delay

      @pool_mutex.synchronize do
        if @stopping_workers
          @queued_delivery_ids.delete(delivery_id)
          @in_flight -= 1 if @in_flight > 0
          @pool_condition.broadcast if @in_flight == 0
          return
        end

        @delayed_delivery_ids << [ready_at, delivery_id]
        @delayed_delivery_ids.sort_by!(&:first)
        @delayed_condition.signal
      end
    end

    def delayed_scheduler_loop
      loop do
        delivery_id = nil

        @pool_mutex.synchronize do
          loop do
            return if @stopping_workers

            if @delayed_delivery_ids.empty?
              @delayed_condition.wait(@pool_mutex)
              next
            end

            ready_at, id = @delayed_delivery_ids.first
            wait_for = ready_at - monotonic_time

            if wait_for <= 0
              @delayed_delivery_ids.shift
              delivery_id = id
              break
            end

            @delayed_condition.wait(@pool_mutex, wait_for)
          end
        end

        @delivery_queue << delivery_id if delivery_id
      end
    end

    def wait_for_delivery_throttles!(delivery, worker_state)
      loop do
        delay = @delivery_action.throttle_delay(delivery, worker_state)
        return unless delay

        sleep_seconds(delay)
      end
    end

    def claim_delivery(delivery)
      attempt = nil

      delivery.with_lock do
        next unless delivery.action == @action
        next unless delivery.due_for_delivery?

        unless delivery.notification_receiver_available?
          delivery.update!(
            state: 'canceled',
            error_summary: 'notification receiver is disabled or muted'
          )
          next
        end

        unless delivery.delivery_method_enabled?
          delivery.update!(
            state: 'canceled',
            error_summary: "#{@action} delivery method is disabled"
          )
          next
        end

        unless delivery.receiver_action_available?
          delivery.update!(
            state: 'canceled',
            error_summary: "#{@action} action is not available"
          )
          next
        end

        RateLimits.with_limit_lock(delivery) do
          limited_until = RateLimits.rate_limited_until_without_lock(delivery, config: @config)
          if limited_until
            delivery.update!(
              state: 'released',
              next_attempt_at: limited_until,
              error_summary: "delivery rate limit reached; next attempt after #{limited_until.iso8601}"
            )
            next
          end

          attempt_number = delivery.attempt_count + 1
          mark_stale_attempts_failed!(delivery) if delivery.sending_state?

          attempt = delivery.event_delivery_attempts.create!(
            action: delivery.action,
            recipient_user: delivery.recipient_user,
            state: 'running',
            attempt_number:,
            started_at: Time.now
          )

          delivery.update!(
            state: 'sending',
            attempt_count: attempt_number,
            last_attempt_at: Time.now,
            next_attempt_at: Time.now + CLAIM_TIMEOUT,
            error_summary: nil
          )
        end
      end

      attempt
    end

    def mark_stale_attempts_failed!(delivery)
      now = Time.now
      delivery.event_delivery_attempts
              .where(state: ::EventDeliveryAttempt.states.fetch('running'))
              .where(finished_at: nil)
              .update_all(
                state: ::EventDeliveryAttempt.states.fetch('failed'),
                finished_at: now,
                error_summary: 'delivery attempt timed out',
                updated_at: now
              )
    end

    def deliver(delivery)
      @delivery_action.deliver(delivery)
    end

    def validate_delivery_result!(result)
      return result if result.is_a?(DeliveryResult)

      actual_type = result.nil? ? 'nil' : result.class.to_s
      raise DeliveryFailure,
            "notification action #{@action.inspect} returned #{actual_type}; expected DeliveryResult"
    end

    def prepare_grouped_delivery!(delivery)
      return unless delivery.grouped_delivery?
      return if delivery_snapshot_prepared?(delivery)

      @delivery_action.prepare_delivery(delivery)
    end

    def delivery_snapshot_prepared?(delivery)
      @delivery_action.prepared?(delivery)
    end

    def mark_success!(delivery, attempt, result)
      now = Time.now

      attempt.update!(
        state: 'succeeded',
        finished_at: now,
        provider_message_id: result.provider_message_id,
        response_status: result.response_status,
        response_body: result.response_body,
        response_headers: result.response_headers,
        error_summary: nil
      )

      delivery.update!(
        state: 'sent',
        next_attempt_at: nil,
        provider_message_id: result.provider_message_id,
        response_status: result.response_status,
        response_body: result.response_body,
        response_headers: result.response_headers,
        error_summary: nil
      )
    end

    def mark_accepted!(delivery, attempt, result)
      now = Time.now

      delivery.with_lock do
        attempt.update!(
          state: 'succeeded',
          finished_at: now,
          provider_message_id: result.provider_message_id,
          response_status: result.response_status,
          response_body: result.response_body,
          response_headers: result.response_headers,
          error_summary: nil
        )

        return if delivery.sent_state? || delivery.failed_state?

        delivery.update!(
          state: 'accepted',
          next_attempt_at: nil,
          provider_message_id: result.provider_message_id,
          response_status: result.response_status,
          response_body: result.response_body,
          response_headers: result.response_headers,
          error_summary: nil
        )
      end
    end

    def mark_failure!(delivery, attempt, response_status:, response_body:, error_summary:, response_headers: nil)
      now = Time.now

      attempt&.update!(
        state: 'failed',
        finished_at: now,
        response_status:,
        response_body:,
        response_headers:,
        error_summary:
      )

      attrs = {
        response_status:,
        response_body:,
        response_headers:,
        error_summary:
      }

      if delivery.attempt_count >= MAX_ATTEMPTS
        attrs[:state] = 'failed'
        attrs[:next_attempt_at] = nil
      else
        attrs[:state] = 'released'
        attrs[:next_attempt_at] = Time.now + backoff_seconds(delivery.attempt_count)
      end

      delivery.update!(attrs)
    end

    def mark_preparation_terminal!(delivery, attempt, error)
      now = Time.now
      attempt&.update!(
        state: 'failed',
        finished_at: now,
        error_summary: error.message
      )
      delivery.update!(
        state: error.delivery_state,
        next_attempt_at: nil,
        error_summary: error.message
      )
    end

    def exception_response_status(error)
      @delivery_action.exception_response_status(error)
    end

    def exception_response_body(error)
      @delivery_action.exception_response_body(error)
    end

    def connection
      @connection ||= Bunny.new(
        hosts: Array(rabbitmq_config.fetch('hosts')),
        vhost: rabbitmq_config.fetch('vhost', '/'),
        username: rabbitmq_config.fetch('username'),
        password: rabbitmq_config.fetch('password'),
        log_file: $stderr
      )
      @connection.start unless @connection.open?
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
      @config.fetch('poll_interval', DEFAULT_POLL_INTERVAL).to_i
    end

    def limit_value
      ENV.fetch('LIMIT', DEFAULT_LIMIT).to_i
    end

    def concurrency
      @concurrency ||= positive_integer_config(
        action_config.fetch('concurrency', @delivery_action.default_concurrency),
        "#{@action}.concurrency"
      )
    end

    def action_config
      @config.fetch(@delivery_action.config_section, {})
    end

    def positive_integer_config(value, name)
      ret = value.to_i
      raise ArgumentError, "#{name} must be at least 1" if ret < 1

      ret
    end

    def inline_delivery_dispatch?
      concurrency == 1 || active_database_transaction?
    end

    def active_database_transaction?
      ActiveRecord::Base.connection.transaction_open?
    rescue StandardError
      false
    end

    def backoff_seconds(attempt_count)
      [60 * (2**[attempt_count - 1, 0].max), 3600].min
    end

    def monotonic_time
      @monotonic_clock.call
    end

    def sleep_seconds(seconds)
      @sleeper.call(seconds)
    end

    def trap_signals
      %w[INT TERM].each do |signal|
        Signal.trap(signal) { @running = false }
      end
    end
  end
end
