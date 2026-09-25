require 'json'
require 'libosctl'
require 'nodectld/exceptions'
require 'nodectld/utils'
require 'nodectld/storage_mutation_receipt'
require 'nodectld/storage_observer_settlement'

module NodeCtld
  class Command
    include Utils::Compat
    include OsCtl::Lib::Utils::Log

    FAILURE_LOG_ERROR_BYTES = 4096

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
      @storage_attempts = []
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

      unless param.is_a?(Hash)
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

      @storage_guard = param['storage_guard']
      if param.has_key?('storage_guard') && !@storage_guard.is_a?(Hash)
        record_output(original_chain_direction, { error: 'Malformed storage guard' })
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

      @time_end = Time.now.utc
    end

    def bad_value(klass)
      raise SystemCommandFailed.new(
        'process handler return value',
        1,
        "#{klass} did not return expected value"
      )
    end

    def save(db)
      seal_interrupted_storage_attempt
      storage_phase = storage_receipt_phase
      @storage_guard_uncertain = true if storage_phase == 5

      db.transaction do |t|
        save_transaction(t, storage_phase)

        if @storage_guard_uncertain
          close_chain(t, true)
          next
        end

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

      post_save_transaction
    end

    def save_transaction(db, storage_phase = nil)
      log(:debug, self, 'Saving transaction')

      if @cmd && current_chain_direction == :execute && @status != :failed &&
         !@storage_guard_uncertain
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

      @storage_attempts.each do |attempt, status, before, after|
        attempt.finish!(db, status, before, after)
      end
      settlement = @unsettled_storage_attempt || @storage_attempts.last&.first
      settlement&.settle!(db, storage_phase) if storage_phase
      return unless storage_phase == 5 && !settlement && @storage_guard

      StorageMutationReceipt.quarantine_guard!(db, @storage_guard, @trans)
    end

    def post_save_transaction
      return unless @cmd && current_chain_direction == :execute && @status != :failed &&
                    !@storage_guard_uncertain

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
      db.prepared(
        'UPDATE transaction_chains
        SET `state` = 3, `progress` = `progress` - 1
        WHERE id = ?',
        chain_id
      )
    end

    def close_chain(db, fatal = false)
      log(:debug, self, 'Close chain')

      state = if fatal
                5
              elsif current_chain_direction == :execute && @status != :failed
                2
              else
                4
              end

      # mark chain as finished
      db.prepared(
        "UPDATE transaction_chains
        SET
          `state` = ?,
          `progress` = #{current_chain_direction == :execute ? '`progress` + 1' : '0'}
        WHERE id = ?",
        state, chain_id
      )

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

      StorageObserverSettlement.settle_chain!(db, chain_id)
    end

    def fail_followers(db)
      log(:debug, self, 'Fail followers')
      db.prepared(
        'UPDATE transactions
        SET done = 1, status = 0, output = ?, finished_at = UTC_TIMESTAMP()
        WHERE
          transaction_chain_id = ?
          AND id > ?',
        output_json(:execute, { error: 'Dependency failed', skipped: true }),
        chain_id,
        id
      )
    end

    def fail_all(db)
      log(:debug, self, 'Fail all')
      db.prepared(
        'UPDATE transactions
        SET done = 1, status = 0, output = ?, finished_at = UTC_TIMESTAMP()
        WHERE
          transaction_chain_id = ?',
        output_json(:execute, { error: 'Chain failed', skipped: true }),
        chain_id
      )
    end

    def killed(hard)
      if type.to_i == 5204 && @storage_guard.is_a?(Hash)
        @status = :failed
        @interrupted_storage_guard = true
        @storage_guard_uncertain = true
        record_output(
          method_direction(@current_method) || current_chain_direction,
          { error: 'Interrupted; storage needs reconciliation' }
        )
        return
      end

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

    def successful_snapshot_execute_identity
      @active_storage_attempt&.successful_execute_identity
    end

    def storage_snapshot_target
      @active_storage_attempt
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
      previous = @@handlers[type]
      if previous && previous != klass
        raise "duplicate command handle #{type}: #{previous} and #{klass}"
      end

      @@handlers[type] = klass
    end

    def self.registered_handlers
      @@handlers.dup
    end

    private

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

      seal_interrupted_storage_attempt if m == :rollback
      return if @storage_guard_uncertain

      if type.to_i == 5204 && @storage_guard
        begin
          @active_storage_attempt = StorageMutationReceipt.new(
            @storage_guard, @trans,
            JSON.parse(@trans['input']).fetch('input'), direction
          ).start!
        rescue StandardError => e
          @status = :failed
          @storage_guard_uncertain = true
          record_output(direction, { error: e.message })
          return
        end
      end

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
        record_storage_attempt(direction)
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
        record_storage_attempt(direction)

        if m == :exec
          handle_exec_failure(klass)
        end
      rescue CommandNotImplemented
        @status = :failed
        @output = { error: 'Command not implemented' }
        record_output(direction, @output)
        record_storage_attempt(direction)
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
        record_storage_attempt(direction)

        if m == :exec
          handle_exec_failure(klass)
        end
      end
    end

    def record_storage_attempt(direction)
      return unless @active_storage_attempt

      before, after = @cmd.storage_observation(direction)
      @storage_attempts << [@active_storage_attempt, @status, before, after]
      @active_storage_attempt = nil
    rescue StandardError
      @storage_guard_uncertain = true
      @unsettled_storage_attempt = @active_storage_attempt
      @active_storage_attempt = nil
    end

    def seal_interrupted_storage_attempt
      return unless @active_storage_attempt

      if @interrupted_storage_guard
        @unsettled_storage_attempt = @active_storage_attempt
        @active_storage_attempt = nil
        return
      end

      @cmd.capture_interrupted_execute_observation
      record_storage_attempt(:execute)
    rescue StandardError
      @storage_guard_uncertain = true
      @unsettled_storage_attempt = @active_storage_attempt
      @active_storage_attempt = nil
    end

    def storage_receipt_phase
      return 5 if @interrupted_storage_guard
      return 5 if @unsettled_storage_attempt
      return 5 if @storage_guard_uncertain && @storage_guard
      return if @storage_attempts.empty?
      return 5 if @active_storage_attempt

      execute = @storage_attempts.find do |attempt, _status, _before, _after|
        attempt.direction == :execute
      end
      rollback = @storage_attempts.find do |attempt, _status, _before, _after|
        attempt.direction == :rollback
      end
      if execute
        _attempt, status, before, after = execute
        created = created_snapshot_evidence?(before, after)
        no_effect = before && %i[present missing].include?(before[:presence]) &&
                    before == after
        if rollback
          _rollback_attempt, rollback_status, rollback_before, rollback_after = rollback
          compensated = created && rollback_status == :ok && rollback_before == after &&
                        missing_after_same_owner?(rollback_before, rollback_after)
          unchanged = no_effect && rollback_status == :ok &&
                      rollback_before == before && rollback_after == before
          return 3 if compensated
          return 4 if unchanged

          return 5
        end
        return 2 if status == :ok && created
        return 4 if status == :failed && no_effect

        return 5
      end

      return 5 unless rollback

      rollback_attempt, status, before, after = rollback
      expected = rollback_attempt.successful_execute_identity
      return 3 if status == :ok && expected &&
                  snapshot_identity(before) == expected &&
                  missing_after_same_owner?(before, after)

      5
    end

    def created_snapshot_evidence?(before, after)
      before && after && before[:presence] == :missing && after[:presence] == :present &&
        before[:path] == after[:path] && before[:owner_guid] == after[:owner_guid] &&
        after[:guid]
    end

    def missing_after_same_owner?(before, after)
      before && after && after[:presence] == :missing &&
        before[:path] == after[:path] && before[:owner_guid] == after[:owner_guid]
    end

    def snapshot_identity(observation)
      return unless observation && observation[:presence] == :present

      { guid: observation[:guid], owner_guid: observation[:owner_guid],
        path_digest: Digest::SHA256.hexdigest(observation[:path]) }
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
