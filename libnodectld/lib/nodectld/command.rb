require 'json'
require 'libosctl'
require 'nodectld/exceptions'
require 'nodectld/transaction_chain_events'
require 'nodectld/utils'

module NodeCtld
  class Command
    include Utils::Compat
    include OsCtl::Lib::Utils::Log

    FAILURE_LOG_ERROR_BYTES = 4096
    EVENT_DELIVERY_STATE_PREPARED = 0
    EVENT_DELIVERY_STATE_RELEASED = 1
    EVENT_DELIVERY_STATE_SKIPPED = 4
    EVENT_DELIVERY_STATE_CANCELED = 6
    EVENT_DELIVERY_STATE_ABORTED = 8
    EVENT_DELIVERY_STATE_GROUPING = 9
    EVENT_ROUTING_STATE_ABORTED = 4
    EVENT_ROUTING_CONTEXT_STATE_ABORTED = 6

    attr_reader :trans

    @@handlers = {}

    def initialize(trans)
      @chain = {
        id: trans['transaction_chain_id'].to_i,
        state: trans['chain_state'].to_i,
        progress: trans['chain_progress'].to_i,
        size: trans['chain_size'].to_i,
        urgent_rollback: trans['chain_urgent_rollback'].to_i == 1
      }
      @trans = trans
      @outputs = load_outputs
      @output = {}
      @status = :failed
      @m_attr = Mutex.new
      @chain_state_changes = []
    end

    def execute
      klass = handler

      unless klass
        record_output(original_chain_direction, { error: 'Unsupported command' })
        rollback_without_execute
        return false
      end

      if @trans['signature'] \
         && !TransactionVerifier.verify_base64(@trans['input'], @trans['signature'])
        record_output(original_chain_direction, { error: 'Invalid signature' })
        rollback_without_execute
        return false
      end

      begin
        input = JSON.parse(@trans['input'])
        param = input['input']
      rescue StandardError
        record_output(original_chain_direction, { error: 'Bad input syntax' })
        rollback_without_execute
        return false
      end

      unless check_signed_opts(input)
        record_output(
          original_chain_direction,
          { error: 'Signed options do not match relational options' }
        )
        rollback_without_execute
        return false
      end

      param[:vps_id] = @trans['vps_id'].to_i

      @cmd = class_from_name(klass).new(self, param)

      @m_attr.synchronize { @time_start = Time.now.utc }

      if original_chain_direction == :execute
        safe_call(klass, :exec)

      elsif reversible?
        safe_call(klass, :rollback)

      else
        @status = :failed
      end

      @time_end = Time.new.utc
    end

    def bad_value(klass)
      raise SystemCommandFailed.new(
        'process handler return value',
        1,
        "#{klass} did not return expected value"
      )
    end

    def save(db)
      db.transaction do |t|
        save_transaction(t)

        if ((@status == :ok || @status == :warning) && !@rolledback) || keep_going?
          # Chain is finished, close up
          if chain_finished?
            run_confirmations(t)
            close_chain(t)

          else # There are more transaction in this chain
            continue_chain(t)
          end

        elsif @status == :failed || @rolledback
          # Fail if already rollbacking
          if original_chain_direction == :rollback && !@rolledback
            log(:critical, :chain, 'Transaction rollback failed, admin intervention is necessary')
            # FIXME: do something

            close_chain(t, true)

          elsif chain_finished? # Reverse chain direction
            # Is it the last transaction to rollback?
            fail_followers(t) if @rolledback

            run_confirmations(t)
            close_chain(t)

          elsif reversible?
            rollback_chain(t)
            fail_followers(t)

          else
            fail_followers(t)
            run_confirmations(t)
            close_chain(t)
          end
        end
      end

      publish_chain_state_changes
      post_save_transaction
    end

    def save_transaction(db)
      log(:debug, self, 'Saving transaction')

      if @cmd && current_chain_direction == :execute && @status != :failed
        @cmd.on_save(db)
        record_output(:execute, @cmd.output)
      end

      done = if current_chain_direction == :execute
               1
             else
               2 # rolled back
             end

      db.prepared(
        'UPDATE transactions
        SET done = ?,
            status = ?,
            output = ?,
            started_at = ?,
            finished_at = ?
        WHERE id = ?',
        done, { failed: 0, ok: 1, warning: 2 }[@status],
        output_json,
        @time_start && @time_start.strftime('%Y-%m-%d %H:%M:%S'),
        @time_end && @time_end.strftime('%Y-%m-%d %H:%M:%S'),
        @trans['id']
      )
    end

    def post_save_transaction
      return unless @cmd && current_chain_direction == :execute && @status != :failed

      @cmd.post_save
    end

    def run_confirmations(t)
      c = Confirmations.new(chain_id)
      c.run(t, current_chain_direction)
    end

    def continue_chain(db)
      log(:debug, self, 'Continue chain')
      db.prepared(
        "UPDATE transaction_chains
        SET `progress` = `progress` #{current_chain_direction == :execute ? '+' : '-'} 1
        WHERE id = ?",
        chain_id
      )
    end

    def rollback_chain(db)
      log(:debug, self, 'Rollback chain')
      record_chain_state_change(@chain[:state], 3)
      db.prepared(
        'UPDATE transaction_chains
        SET `state` = 3, `progress` = `progress` - 1
        WHERE id = ?',
        chain_id
      )
      abort_unsent_event_deliveries(db)
    end

    def close_chain(db, fatal = false)
      log(:debug, self, 'Close chain')

      direction = current_chain_direction
      state = if fatal
                5
              elsif direction == :execute && @status != :failed
                2
              else
                4
              end
      record_chain_state_change(@chain[:state], state)

      # mark chain as finished
      db.prepared(
        "UPDATE transaction_chains
        SET
          `state` = ?,
          `progress` = #{direction == :execute ? '`progress` + 1' : '0'}
        WHERE id = ?",
        state, chain_id
      )
      abort_unsent_event_deliveries(db) if [4, 5].include?(state)

      # remove signature from all transactions
      db.prepared(
        'UPDATE transactions SET signature = NULL WHERE transaction_chain_id = ?',
        chain_id
      )

      # release all locks
      return if fatal

      db.prepared(
        "DELETE FROM resource_locks
          WHERE
            locked_by_type = 'TransactionChain' AND locked_by_id = ?",
        chain_id
      )

      # release ports
      db.prepared(
        'UPDATE port_reservations
          SET transaction_chain_id = NULL, addr = NULL
          WHERE transaction_chain_id = ?',
        chain_id
      )
    end

    def fail_followers(db)
      log(:debug, self, 'Fail followers')
      db.prepared(
        'UPDATE transactions
        SET done = 1, status = 0, output = ?
        WHERE
          transaction_chain_id = ?
          AND id > ?',
        output_json(:execute, { error: 'Dependency failed' }),
        chain_id,
        id
      )
    end

    def fail_all(db)
      log(:debug, self, 'Fail all')
      db.prepared(
        'UPDATE transactions
        SET done = 1, status = 0, output = ?
        WHERE
          transaction_chain_id = ?',
        output_json(:execute, { error: 'Chain failed' }),
        chain_id
      )
    end

    def abort_unsent_event_deliveries(db)
      log(:debug, self, 'Abort unsent transaction-gated event deliveries')

      event_ids = []
      group_ids = []
      rows = db.prepared(<<~SQL, chain_id)
        SELECT DISTINCT ed.event_id, ed.event_delivery_group_id
        FROM event_deliveries ed
        INNER JOIN transactions t ON t.id = ed.transaction_id
        LEFT JOIN event_delivery_attempts a ON a.event_delivery_id = ed.id
        WHERE t.transaction_chain_id = ?
          AND ed.state IN (
            #{EVENT_DELIVERY_STATE_PREPARED},
            #{EVENT_DELIVERY_STATE_RELEASED},
            #{EVENT_DELIVERY_STATE_GROUPING}
          )
          AND ed.attempt_count = 0
          AND ed.provider_message_id IS NULL
          AND a.id IS NULL
      SQL
      rows.each do |row|
        event_ids << row.fetch('event_id').to_i
        group_id = row['event_delivery_group_id']
        group_ids << group_id.to_i if group_id
      end
      return if event_ids.empty?

      group_ids.uniq.sort.each do |group_id|
        db.prepared(
          'SELECT id FROM event_delivery_groups WHERE id = ? FOR UPDATE',
          group_id
        ).get
      end

      now = Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      db.prepared(
        <<~SQL,
          UPDATE event_deliveries ed
          INNER JOIN transactions t ON t.id = ed.transaction_id
          LEFT JOIN event_delivery_attempts a ON a.event_delivery_id = ed.id
          SET ed.state = ?,
              ed.next_attempt_at = NULL,
              ed.error_summary = ?,
              ed.updated_at = ?
          WHERE t.transaction_chain_id = ?
            AND ed.state IN (?, ?, ?)
            AND ed.attempt_count = 0
            AND ed.provider_message_id IS NULL
            AND a.id IS NULL
        SQL
        EVENT_DELIVERY_STATE_ABORTED,
        "transaction chain ##{chain_id} failed before notification was sent",
        now,
        chain_id,
        EVENT_DELIVERY_STATE_PREPARED,
        EVENT_DELIVERY_STATE_RELEASED,
        EVENT_DELIVERY_STATE_GROUPING
      )

      group_ids.uniq.sort.each { |group_id| recompute_event_delivery_group(db, group_id, now) }
      event_ids.uniq.each { |event_id| recompute_aborted_event_state(db, event_id, now) }
    end

    def recompute_event_delivery_group(db, group_id, now)
      group = db.prepared(
        'SELECT group_wait_seconds, group_interval_seconds, last_sealed_at
         FROM event_delivery_groups
         WHERE id = ?
         FOR UPDATE',
        group_id
      ).get
      return if group.nil?

      member = db.prepared(
        'SELECT released_at
         FROM event_deliveries
         WHERE event_delivery_group_id = ? AND state = ?
         ORDER BY released_at, id
         LIMIT 1',
        group_id,
        EVENT_DELIVERY_STATE_GROUPING
      ).get

      next_flush_at = if member
                        wait_deadline =
                          member.fetch('released_at') + group.fetch('group_wait_seconds').to_i
                        last_sealed_at = group['last_sealed_at']
                        interval_deadline =
                          last_sealed_at &&
                          (last_sealed_at + group.fetch('group_interval_seconds').to_i)
                        [wait_deadline, interval_deadline].compact.max
                      end

      db.prepared(
        'UPDATE event_delivery_groups
         SET next_flush_at = ?, updated_at = ?
         WHERE id = ?',
        next_flush_at,
        now,
        group_id
      )
    end

    def recompute_aborted_event_state(db, event_id, now)
      row = db.prepared(
        <<~SQL,
          SELECT
            SUM(CASE WHEN state = ? THEN 1 ELSE 0 END) AS aborted_count,
            SUM(CASE WHEN state NOT IN (?, ?, ?) THEN 1 ELSE 0 END) AS active_count
          FROM event_deliveries
          WHERE event_id = ?
        SQL
        EVENT_DELIVERY_STATE_ABORTED,
        EVENT_DELIVERY_STATE_SKIPPED,
        EVENT_DELIVERY_STATE_CANCELED,
        EVENT_DELIVERY_STATE_ABORTED,
        event_id
      ).get

      if row && row.fetch('aborted_count').to_i > 0 && row.fetch('active_count').to_i == 0
        db.prepared(
          'UPDATE events SET routing_state = ?, updated_at = ? WHERE id = ?',
          EVENT_ROUTING_STATE_ABORTED,
          now,
          event_id
        )
      end

      db.prepared(
        'SELECT DISTINCT event_routing_context_id AS id
         FROM event_deliveries
         WHERE event_id = ? AND event_routing_context_id IS NOT NULL',
        event_id
      ).each do |context_row|
        recompute_aborted_context_state(db, context_row.fetch('id').to_i, now)
      end
    end

    def recompute_aborted_context_state(db, context_id, now)
      row = db.prepared(
        <<~SQL,
          SELECT
            SUM(CASE WHEN state = ? THEN 1 ELSE 0 END) AS aborted_count,
            SUM(CASE WHEN state NOT IN (?, ?, ?) THEN 1 ELSE 0 END) AS active_count
          FROM event_deliveries
          WHERE event_routing_context_id = ?
        SQL
        EVENT_DELIVERY_STATE_ABORTED,
        EVENT_DELIVERY_STATE_SKIPPED,
        EVENT_DELIVERY_STATE_CANCELED,
        EVENT_DELIVERY_STATE_ABORTED,
        context_id
      ).get
      return unless row && row.fetch('aborted_count').to_i > 0 && row.fetch('active_count').to_i == 0

      db.prepared(
        'UPDATE event_routing_contexts SET routing_state = ?, updated_at = ? WHERE id = ?',
        EVENT_ROUTING_CONTEXT_STATE_ABORTED,
        now,
        context_id
      )
    end

    def killed(hard)
      return unless hard

      @status = :failed
      record_output(
        method_direction(@current_method) || current_chain_direction,
        { error: 'Killed' }
      )

      return unless @current_method == :exec

      if keep_going?
        log(:debug, self, 'Transaction failed but keep going on')

      elsif reversible?
        log(:debug, self, 'Transaction failed, running rollback')
        @rolledback = true
        safe_call(@current_klass, :rollback)

      else
        log(:debug, self, 'Transaction failed and is irreversible')
      end
    end

    def chain_id
      @chain[:id]
    end

    alias worker_id chain_id

    def id
      @trans['id']
    end

    def type
      @trans['handle']
    end

    def queue
      @trans['queue'].to_sym
    end

    def priority
      @trans['priority']
    end

    def urgent?
      @trans['urgent'].to_i == 1 \
        || (original_chain_direction == :execute && @chain[:urgent_rollback])
    end

    def handler
      @@handlers[@trans['handle'].to_i]
    end

    def step
      @cmd && @cmd.step
    end

    def subtask
      @cmd && @cmd.subtask
    end

    def time_start
      @m_attr.synchronize { @time_start && @time_start.clone }
    end

    def progress
      @m_attr.synchronize { @progress && @progress.clone }
    end

    def progress=(v)
      @m_attr.synchronize { @progress = v }
    end

    def current_chain_direction
      if @rolledback
        :rollback
      else
        original_chain_direction
      end
    end

    def original_chain_direction
      if @chain[:state] == 3 || @rolledback
        :rollback
      else
        :execute
      end
    end

    def log_type
      "chain=#{chain_id},trans=#{id},type=#{current_chain_direction}"
    end

    def self.register(klass, type)
      @@handlers[type] = klass
    end

    private

    def record_chain_state_change(previous_state, state)
      return if previous_state.to_i == state.to_i

      @chain_state_changes << [previous_state.to_i, state.to_i]
      @chain[:state] = state.to_i
    end

    def publish_chain_state_changes
      @chain_state_changes.each do |previous_state, state|
        NodeCtld::TransactionChainEvents.publish(
          chain_id:,
          previous_state:,
          state:
        )
      rescue StandardError => e
        log(:warn, "unable to publish transaction chain event: #{e.class}: #{e.message}")
      end
    end

    def load_outputs
      raw = trans['output']
      return {} if raw.nil? || raw.empty?

      parsed = JSON.parse(raw)
      return {} unless parsed.is_a?(Hash)

      if direction_outputs?(parsed)
        parsed
      else
        { legacy_output_direction.to_s => with_status(parsed, transaction_status) }
      end
    rescue JSON::ParserError
      {
        legacy_output_direction.to_s => with_status(
          { error: raw.to_s },
          transaction_status
        )
      }
    end

    def direction_outputs?(output)
      output.has_key?('execute') || output.has_key?('rollback')
    end

    def legacy_output_direction
      trans['done'].to_i == 2 ? :rollback : :execute
    end

    def transaction_status
      { 0 => :failed, 1 => :ok, 2 => :warning }.fetch(trans['status'].to_i, :failed)
    end

    def method_direction(m)
      case m
      when :exec
        :execute
      when :rollback
        :rollback
      end
    end

    def with_status(output, status)
      stringify_keys(output).merge('status' => status.to_s)
    end

    def stringify_keys(hash)
      hash.each_with_object({}) do |(k, v), ret|
        ret[k.to_s] = v
      end
    end

    def output_delta(before, after)
      after.reject { |k, v| before[k] == v }
    end

    def record_output(direction, output = {}, status: @status)
      @outputs[direction.to_s] ||= {}
      formatted_output = with_status(output, status)
      @outputs[direction.to_s].merge!(formatted_output)
      log_failure_output(direction, formatted_output)
    end

    def log_failure_output(direction, output)
      return unless output['status'] == 'failed'

      log(
        :error,
        failure_log_type(direction),
        failure_log_message(output)
      )
    end

    def failure_log_type(direction)
      parts = [
        "chain=#{chain_id}",
        "trans=#{id}",
        "direction=#{direction}",
        "handle=#{type}"
      ]
      klass = @current_klass || handler
      parts << "handler=#{klass}" if klass
      parts.join(',')
    end

    def failure_log_message(output)
      parts = ['Transaction failed']
      parts << "cmd=#{log_value(output['cmd'])}" if output.has_key?('cmd')
      if output.has_key?('exitstatus')
        parts << "exitstatus=#{log_value(output['exitstatus'])}"
      end
      if output.has_key?('error')
        parts << "error=#{log_value(output['error'], max_bytes: FAILURE_LOG_ERROR_BYTES)}"
      end
      parts.join(' ')
    end

    def log_value(value, max_bytes: nil)
      ret = value.to_s.encode(
        Encoding::UTF_8,
        invalid: :replace,
        undef: :replace,
        replace: '?'
      ).gsub(/[[:space:]]+/, ' ').strip

      if max_bytes && ret.bytesize > max_bytes
        "#{ret.byteslice(0, max_bytes).scrub('?')}..."
      else
        ret
      end
    end

    def output_json(direction = nil, output = {}, status: :failed)
      if direction
        { direction.to_s => with_status(output, status) }.to_json
      else
        @outputs.to_json
      end
    end

    def check_signed_opts(input)
      input['transaction_chain'] == trans['transaction_chain_id'] \
        && input['depends_on'] == trans['depends_on_id'] \
        && input['handle'] == trans['handle'] \
        && input['node'] == trans['node_id'] \
        && input['reversible'] == trans['reversible']
    end

    def rollback_without_execute
      return unless original_chain_direction == :execute && reversible?

      @rolledback = true
    end

    def safe_call(klass, m)
      @current_klass = klass
      @current_method = m
      direction = method_direction(m)
      handler_output_before = @cmd.output.clone

      begin
        ret = @cmd.send(m)

        if ret.is_a?(OsCtl::Lib::SystemCommandResult)
          @status = :ok
        elsif ret.is_a?(::Hash)
          @status = ret[:ret]
          bad_value(klass) if @status.nil?
        else
          bad_value(klass)
        end

        record_output(
          direction,
          output_delta(handler_output_before, @cmd.output)
        )
      rescue SystemCommandFailed => e
        @status = :failed
        @output = {
          cmd: e.cmd,
          exitstatus: e.rc,
          error: e.output.byteslice(0, 2**15)
        }
        record_output(
          direction,
          @output.merge(output_delta(handler_output_before, @cmd.output))
        )

        if m == :exec
          handle_exec_failure(klass)
        end
      rescue CommandNotImplemented
        @status = :failed
        @output = { error: 'Command not implemented' }
        record_output(direction, @output)
        rollback_without_execute if m == :exec
      rescue StandardError => e
        @status = :failed
        @output = {
          error: e.inspect,
          backtrace: e.backtrace
        }
        record_output(
          direction,
          @output.merge(output_delta(handler_output_before, @cmd.output))
        )

        if m == :exec
          handle_exec_failure(klass)
        end
      end
    end

    def handle_exec_failure(klass)
      if keep_going?
        log(:debug, self, 'Transaction failed but keep going on')

      elsif reversible?
        log(:debug, self, 'Transaction failed, running rollback')
        @rolledback = true
        safe_call(klass, :rollback)

      else
        log(:debug, self, 'Transaction failed and is irreversible')
      end
    end

    def chain_finished?
      if current_chain_direction == :execute
        @chain[:size] == @chain[:progress] + 1
      else
        # Must check <= 0, because chain might contain a single transaction,
        # and when that fails, the result is -1.
        @chain[:progress] <= 0
      end
    end

    def reversible?
      @trans['reversible'].to_i == 1
    end

    def keep_going?
      @trans['reversible'].to_i == 2
    end
  end
end
