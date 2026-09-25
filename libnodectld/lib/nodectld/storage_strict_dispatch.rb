require 'digest'
require 'json'
require 'nodectld/storage_effect_registry'
require 'nodectld/storage_mutation_receipt'
require 'nodectld/storage_group_snapshot_receipt'
require 'nodectld/transaction_verifier'

module NodeCtld
  # Test-only pre-dispatch policy. Production Command instances do not enable it.
  class StorageStrictDispatch
    class Refused < StandardError; end
    class Uncertain < StandardError; end
    MAX_CHAIN_TRANSACTIONS = 256

    def self.check!(trans, direction, handler: nil, prior_execute: nil, &on_guard)
      entry = StorageEffectRegistry.fetch!(trans.fetch('handle'))
      support = entry.public_send("#{direction}_strict_support")
      case support
      when :proved_no_storage_effect
        true
      when :guarded_5204_v1
        check_snapshot!(trans, direction, handler:, &on_guard)
      when :guarded_5215_v1
        check_group!(trans, direction, handler:, prior_execute:, &on_guard)
      else
        raise Refused, "unsupported storage effect #{trans['handle']} #{direction}"
      end
    rescue StorageEffectRegistry::Unclassified => e
      raise Refused, e.message
    end

    def self.signed_snapshot!(trans)
      raise Refused, 'strict snapshot has no signature' if trans['signature'].to_s.empty?

      verified = begin
        TransactionVerifier.verify_base64(trans['input'], trans['signature'])
      rescue StandardError
        false
      end
      unless verified
        raise Refused, 'strict snapshot signature is invalid'
      end

      input = JSON.parse(trans.fetch('input'))
      raise Refused, 'strict snapshot input is malformed' unless input.is_a?(Hash) && input['input'].is_a?(Hash)
      unless input['transaction_chain'] == trans['transaction_chain_id'] &&
             input['depends_on'] == trans['depends_on_id'] &&
             input['handle'] == trans['handle'] && input['node'] == trans['node_id'] &&
             input['reversible'] == trans['reversible']
        raise Refused, 'strict snapshot signed options do not match command'
      end

      params = input.fetch('input')
      guard = params['storage_guard']
      raise Refused, 'strict snapshot guard is missing' unless guard.is_a?(Hash)
      raise Refused, 'strict snapshot guard version is unsupported' unless
        guard['registry_version'] == StorageEffectRegistry::VERSION &&
        guard['protocol_version'] == 1
      raise Refused, 'strict snapshot guard binding is malformed' unless
        guard['token'].is_a?(String) && guard['token'].match?(/\A[0-9a-f]{64}\z/) &&
        guard['manifest_digest'].is_a?(String) &&
        guard['manifest_digest'].match?(/\A[0-9a-f]{64}\z/)
      raise Refused, 'strict snapshot parameters are malformed' unless
        params['snapshot_id'].is_a?(Integer) && params['snapshot_id'] > 0 &&
        params['pool_fs'].is_a?(String) && !params['pool_fs'].empty? &&
        params['dataset_name'].is_a?(String) && !params['dataset_name'].empty? &&
        params['planned_snapshot_name'].is_a?(String) &&
        params['planned_snapshot_name'].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\z/)

      [params, guard, Digest::SHA256.hexdigest(trans.fetch('input'))]
    rescue JSON::ParserError, KeyError, TypeError => e
      raise Refused, "strict snapshot input is malformed: #{e.class}"
    end

    def self.check_snapshot!(trans, direction, handler:)
      raise Refused, 'snapshot handler unavailable' unless handler

      params, guard, input_digest = signed_snapshot!(trans)
      yield guard if block_given?
      begin
        StorageMutationReceipt.new(
          guard, trans, params, direction,
          strict: true,
          strict_signed_input_digest: input_digest
        ).strict_preflight!
      rescue StorageMutationReceipt::BindingRefused => e
        raise Refused, e.message
      rescue StandardError
        raise Uncertain, 'strict snapshot receipt cannot be proved'
      end
      input_digest
    end
    private_class_method :check_snapshot!

    def self.signed_group!(trans)
      raise Refused, 'strict group has no signature' if trans['signature'].to_s.empty?

      verified = begin
        TransactionVerifier.verify_base64(trans['input'], trans['signature'])
      rescue StandardError
        false
      end
      raise Refused, 'strict group signature is invalid' unless verified

      input = JSON.parse(trans.fetch('input'))
      raise Refused, 'strict group input is malformed' unless input.is_a?(Hash) && input['input'].is_a?(Hash)
      raise Refused, 'strict group signed options differ from command' unless
        input['transaction_chain'] == trans['transaction_chain_id'] &&
        input['depends_on'] == trans['depends_on_id'] &&
        input['handle'] == trans['handle'] && input['node'] == trans['node_id'] &&
        input['reversible'] == trans['reversible']

      params = input.fetch('input')
      guard = params['storage_guard']
      rows = params['snapshots']
      name = params['planned_snapshot_name']
      raise Refused, 'strict group guard is missing or unsupported' unless
        guard.is_a?(Hash) && guard['registry_version'] == StorageEffectRegistry::VERSION &&
        guard['protocol_version'] == 1 &&
        %w[token manifest_digest].all? do |key|
          guard[key].is_a?(String) && guard[key].match?(/\A[0-9a-f]{64}\z/)
        end
      raise Refused, 'strict group members are malformed' unless
        rows.is_a?(Array) && rows.length.between?(1, StorageGroupSnapshotReceipt::MAX_MEMBERS) &&
        name.is_a?(String) && name.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\z/) &&
        rows.all? do |row|
          row.is_a?(Hash) && row.keys.sort == %w[dataset_name pool_fs snapshot_id] &&
          row['snapshot_id'].is_a?(Integer) && row['snapshot_id'] > 0 &&
          row['pool_fs'].is_a?(String) && !row['pool_fs'].empty? &&
          row['dataset_name'].is_a?(String) && !row['dataset_name'].empty?
        end
      raise Refused, 'strict group members are duplicated' unless
        rows.map { |row| row['snapshot_id'] }.uniq.length == rows.length &&
        rows.map { |row| [row['pool_fs'], row['dataset_name']] }.uniq.length == rows.length

      [params, guard, Digest::SHA256.hexdigest(trans.fetch('input'))]
    rescue JSON::ParserError, KeyError, TypeError
      raise Refused, 'strict group input is malformed'
    end

    def self.check_group!(trans, direction, handler:, prior_execute:)
      raise Refused, 'group snapshot handler unavailable' unless handler

      params, guard, digest = signed_group!(trans)
      yield guard if block_given?
      receipt = StorageGroupSnapshotReceipt.new(
        guard, trans, params, direction, signed_input_digest: digest,
                                         prior_execute:
      )
      begin
        receipt.strict_preflight!
      rescue StorageGroupSnapshotReceipt::BindingRefused => e
        raise Refused, e.message
      rescue StandardError
        raise Uncertain, 'strict group snapshot receipt cannot be proved'
      end
      yield guard, receipt if block_given?
      digest
    end
    private_class_method :check_group!

    def self.prove_chain!(db, chain_id:, current_id:)
      chain = db.prepared('SELECT size, state FROM transaction_chains WHERE id = ? FOR UPDATE',
                          chain_id).get
      raise Refused, 'strict chain state is unavailable' unless chain
      raise Refused, 'strict chain state is unavailable' unless [1, 3].include?(chain['state'].to_i)

      members = []
      db.prepared(
        'SELECT id, handle, node_id, depends_on_id, reversible, input, signature, ' \
        'transaction_chain_id, done, status, output, finished_at FROM transactions ' \
        'WHERE transaction_chain_id = ? ORDER BY id LIMIT 257 FOR UPDATE', chain_id
      ).each { |row| members << row }
      raise Refused, 'strict chain is oversized or incomplete' unless
        members.length == chain['size'].to_i && members.length.between?(1, MAX_CHAIN_TRANSACTIONS)
      raise Refused, 'current transaction is not in strict chain' unless
        members.any? { |member| member['id'].to_i == current_id.to_i }
      if members.any? { |member| member['handle'].to_i == 5215 } && members.length != 1
        raise Refused, 'strict group requires a sole 5215 chain member'
      end

      guarded = 0
      members.each do |member|
        raise Refused, 'strict chain has an incomplete transaction' unless complete_member?(member)

        entry = StorageEffectRegistry.fetch!(member['handle'])
        if entry.execute_strict_support == :proved_no_storage_effect &&
           entry.rollback_strict_support == :proved_no_storage_effect
          next
        end

        support = entry.execute_strict_support
        unless %i[guarded_5204_v1 guarded_5215_v1].include?(support) &&
               entry.rollback_strict_support == support
          raise Refused, 'strict chain contains an unproved storage effect'
        end

        guarded += 1
        raise Refused, 'strict chain has multiple guarded snapshots' if guarded > 1

        if support == :guarded_5204_v1
          prove_persisted_snapshot!(db, member)
        else
          prove_persisted_group!(db, member)
        end
      end

      true
    rescue StorageEffectRegistry::Unclassified => e
      raise Refused, e.message
    end

    def self.quarantine_started!(db, chain_id)
      ids = []
      db.prepared(
        'SELECT DISTINCT intent.id FROM storage_mutation_intents intent ' \
        'JOIN storage_mutation_attempts attempt ON attempt.storage_mutation_intent_id = intent.id ' \
        'WHERE intent.transaction_chain_id = ? AND attempt.state = 0 LIMIT 257 FOR UPDATE',
        chain_id
      ).each { |row| ids << row['id'] }
      raise Refused, 'strict chain has too many started attempts' if ids.length > MAX_CHAIN_TRANSACTIONS

      ids.each { |id| StorageMutationReceipt.quarantine_intent!(db, id) }
    end

    def self.complete_member?(member)
      done = member['done'].to_i
      return false unless [1, 2].include?(done) && member['finished_at']

      output = JSON.parse(member['output'])
      direction = done == 2 ? 'rollback' : 'execute'
      output.is_a?(Hash) && output[direction].is_a?(Hash) &&
        %w[ok warning failed].include?(output[direction]['status'])
    rescue JSON::ParserError, TypeError
      false
    end
    private_class_method :complete_member?

    def self.prove_persisted_snapshot!(db, member)
      params, guard, input_digest = signed_snapshot!(member)
      receipt = StorageMutationReceipt.new(
        guard, member, params, :execute,
        strict: true,
        strict_signed_input_digest: input_digest
      )
      intent, target = receipt.strict_terminal_binding!(db)
      raise Refused, 'strict snapshot intent is not unique' unless
        unique_row?(db, 'SELECT id FROM storage_mutation_intents WHERE transaction_id = ? LIMIT 2',
                    member['id'], intent['id'])

      attempts = []
      db.prepared(
        'SELECT id, command_key, attempt_number, direction, state, ' \
        'strict_dispatch_registry_version, strict_signed_input_digest, ' \
        'before_digest, after_digest, receipt_digest, started_at, finished_at ' \
        'FROM storage_mutation_attempts WHERE storage_mutation_intent_id = ? ' \
        'ORDER BY id LIMIT 3 FOR UPDATE', intent['id']
      ).each { |row| attempts << row }
      raise Refused, 'strict snapshot has no exact terminal attempts' unless
        attempts.length.between?(1, 2) &&
        attempts.map { |row| row['direction'].to_i }.uniq.length == attempts.length &&
        attempts.first['direction'].to_i == 0

      attempts.each do |attempt|
        raise Refused, 'strict snapshot attempt provenance does not match signed input' unless
          attempt['command_key'] == '5204' && attempt['attempt_number'].to_i == 1 &&
          attempt['strict_dispatch_registry_version'].to_i == StorageEffectRegistry::VERSION &&
          attempt['strict_signed_input_digest'] == input_digest &&
          attempt['started_at'] && attempt['finished_at'] &&
          %w[before_digest after_digest receipt_digest].all? do |key|
            attempt[key].to_s.match?(/\A[0-9a-f]{64}\z/)
          end
      end

      execute = attempts.first
      execute_observation = exact_observation!(db, execute['id'], target)
      rollback = attempts[1]
      rollback_observation = exact_observation!(db, rollback['id'], target) if rollback
      prove_snapshot_phase!(member, intent['phase'].to_i, execute,
                            execute_observation, rollback, rollback_observation)
    rescue StorageMutationReceipt::BindingRefused, StorageMutationReceipt::UnsettledAttempt => e
      raise Refused, e.message
    end
    private_class_method :prove_persisted_snapshot!

    def self.prove_persisted_group!(db, member)
      params, guard, input_digest = signed_group!(member)
      receipt = StorageGroupSnapshotReceipt.new(
        guard, member, params, :execute, signed_input_digest: input_digest
      )
      intent, targets = receipt.strict_terminal_binding!(db)
      raise Refused, 'strict group intent is not unique' unless
        unique_row?(db, 'SELECT id FROM storage_mutation_intents WHERE transaction_id = ? LIMIT 2',
                    member['id'], intent['id'])

      attempts = []
      db.prepared(
        'SELECT id, command_key, attempt_number, direction, state, ' \
        'strict_dispatch_registry_version, strict_signed_input_digest, ' \
        'before_digest, after_digest, receipt_digest, started_at, finished_at ' \
        'FROM storage_mutation_attempts WHERE storage_mutation_intent_id = ? ' \
        'ORDER BY id LIMIT 3 FOR UPDATE', intent['id']
      ).each { |row| attempts << row }
      raise Refused, 'strict group has incomplete attempts' unless
        attempts.length.between?(1, 2) &&
        attempts.map { |row| row['direction'].to_i } == (0...attempts.length).to_a

      output = JSON.parse(member['output'])
      observations = attempts.map do |attempt|
        direction = attempt['direction'].to_i == 0 ? 'execute' : 'rollback'
        status = output.dig(direction, 'status')
        raise Refused, 'strict group attempt provenance is invalid' unless
          attempt['command_key'] == '5215' && attempt['attempt_number'].to_i == 1 &&
          attempt['strict_dispatch_registry_version'].to_i == StorageEffectRegistry::VERSION &&
          attempt['strict_signed_input_digest'] == input_digest &&
          attempt['started_at'] && attempt['finished_at'] &&
          %w[ok failed].include?(status) &&
          attempt['state'].to_i == (status == 'ok' ? 1 : 2)

        before, after = exact_group_observations!(db, attempt, targets)
        expected_before = StorageGroupSnapshotReceipt.aggregate_digest(targets, before)
        expected_after = StorageGroupSnapshotReceipt.aggregate_digest(targets, after)
        expected_receipt = StorageMutationReceipt.strict_receipt_digest(
          attempt['direction'], status, expected_before, expected_after
        )
        raise Refused, 'strict group aggregate receipt differs from observations' unless
          attempt['before_digest'] == expected_before &&
          attempt['after_digest'] == expected_after &&
          attempt['receipt_digest'] == expected_receipt

        [before, after]
      end

      execute_before, execute_after = observations.first
      created = execute_before.zip(execute_after).map do |prior, current|
        StorageGroupSnapshotReceipt.created?(prior, current)
      end
      unchanged = execute_before.zip(execute_after).map do |prior, current|
        StorageGroupSnapshotReceipt.same?(prior, current) && prior[:presence] == :missing
      end
      raise Refused, 'strict group execute prestate was not missing' unless
        execute_before.all? { |item| item[:presence] == :missing }
      raise Refused, 'strict group execute has ambiguous target' unless
        created.zip(unchanged).all? { |made, same| made || same }

      rollback = observations[1]
      phase = intent['phase'].to_i
      proved = case phase
               when 2
                 !rollback && created.all? && output.dig('execute', 'status') == 'ok' &&
                 member['done'].to_i == 1 && member['status'].to_i == 1
               when 3
                 rollback && created.any? &&
                 output.dig('rollback', 'status') == 'ok' &&
                 %w[ok failed].include?(output.dig('execute', 'status')) &&
                 member['done'].to_i == 2 && member['status'].to_i == 1 &&
                 group_compensated?(execute_after, rollback, created)
               when 4
                 if rollback
                   unchanged.all? && output.dig('execute', 'status') == 'failed' &&
                     output.dig('rollback', 'status') == 'ok' &&
                     rollback[0] == execute_after && rollback[1] == execute_before &&
                     member['done'].to_i == 2 && member['status'].to_i == 1
                 else
                   unchanged.all? && output.dig('execute', 'status') == 'failed' &&
                     member['done'].to_i == 1 && member['status'].to_i == 0
                 end
               else
                 false
               end
      raise Refused, 'strict group terminal phase is unproved' unless proved
    rescue JSON::ParserError, TypeError, StorageGroupSnapshotReceipt::BindingRefused,
           StorageGroupSnapshotReceipt::UnsettledAttempt => e
      raise Refused, "strict group terminal proof failed: #{e.class}"
    end
    private_class_method :prove_persisted_group!

    def self.exact_group_observations!(db, attempt, targets)
      rows = []
      db.prepared(
        'SELECT storage_mutation_target_id, before_presence, after_presence, ' \
        'before_path_digest, after_path_digest, before_graph_digest, after_graph_digest, ' \
        'before_guid, after_guid, before_owner_fs_guid, after_owner_fs_guid ' \
        'FROM storage_mutation_target_observations WHERE storage_mutation_attempt_id = ? ' \
        'LIMIT 33 FOR UPDATE', attempt['id']
      ).each { |row| rows << row }
      raise Refused, 'strict group observations are incomplete' unless rows.length == targets.length

      before = []
      after = []
      targets.each do |target|
        matches = rows.select { |row| row['storage_mutation_target_id'].to_i == target[:id] }
        raise Refused, 'strict group target observation is missing or duplicated' unless matches.one?

        row = matches.first
        digest = Digest::SHA256.hexdigest(target[:path])
        raise Refused, 'strict group observation path or owner differs' unless
          row['before_path_digest'] == digest && row['after_path_digest'] == digest &&
          row['before_owner_fs_guid']&.to_i&.to_s == target[:owner_guid] &&
          row['after_owner_fs_guid']&.to_i&.to_s == target[:owner_guid]

        before << group_observation(row, 'before', target)
        after << group_observation(row, 'after', target)
      end
      [before, after]
    end
    private_class_method :exact_group_observations!

    def self.group_observation(row, prefix, target)
      presence = { 1 => :present, 2 => :missing }[row["#{prefix}_presence"].to_i]
      raise Refused, 'strict group observation presence is unknown' unless presence

      digest = row["#{prefix}_graph_digest"]
      raise Refused, 'strict group dependency digest is missing' unless
        digest.to_s.match?(/\A[0-9a-f]{64}\z/)
      if presence == :missing &&
         (row["#{prefix}_guid"] || digest != StorageGroupSnapshotReceipt::EMPTY_GRAPH_DIGEST)
        raise Refused, 'strict group missing target has contradictory identity'
      end

      { presence:, path: target[:path], owner_guid: target[:owner_guid],
        guid: row["#{prefix}_guid"]&.to_i&.to_s, graph_digest: digest,
        empty_dependencies: digest == StorageGroupSnapshotReceipt::EMPTY_GRAPH_DIGEST }
    end
    private_class_method :group_observation

    def self.group_compensated?(execute_after, rollback, created)
      before, after = rollback
      return false unless before == execute_after

      before.zip(after, created).all? do |prior, current, made|
        if made
          StorageGroupSnapshotReceipt.compensated?(prior, current)
        else
          prior == current && prior[:presence] == :missing
        end
      end
    end
    private_class_method :group_compensated?

    def self.unique_row?(db, sql, key, expected_id)
      rows = []
      db.prepared(sql, key).each { |row| rows << row }
      rows.length == 1 && rows.first['id'].to_i == expected_id.to_i
    end
    private_class_method :unique_row?

    def self.exact_observation!(db, attempt_id, target)
      rows = []
      db.prepared(
        'SELECT storage_mutation_target_id, before_presence, after_presence, ' \
        'before_path_digest, after_path_digest, before_guid, after_guid, ' \
        'before_owner_fs_guid, after_owner_fs_guid ' \
        'FROM storage_mutation_target_observations ' \
        'WHERE storage_mutation_attempt_id = ? LIMIT 2 FOR UPDATE', attempt_id
      ).each { |row| rows << row }
      digest = Digest::SHA256.hexdigest(target['expected_path'])
      owner = target['expected_owner_fs_guid'].to_i.to_s
      row = rows.first
      raise Refused, 'strict snapshot observation is missing or mismatched' unless
        rows.length == 1 && row['storage_mutation_target_id'].to_i == target['id'].to_i &&
        row['before_path_digest'] == digest && row['after_path_digest'] == digest &&
        row['before_owner_fs_guid']&.to_i&.to_s == owner &&
        row['after_owner_fs_guid']&.to_i&.to_s == owner

      row
    end
    private_class_method :exact_observation!

    def self.prove_snapshot_phase!(member, phase, execute, before_after, rollback, rollback_after)
      output = JSON.parse(member['output'])
      execute_status = output.dig('execute', 'status')
      rollback_status = output.dig('rollback', 'status')
      done = member['done'].to_i
      status = member['status'].to_i
      created = before_after['before_presence'].to_i == 2 &&
                before_after['after_presence'].to_i == 1 &&
                before_after['before_guid'].nil? &&
                positive_guid?(before_after['after_guid'])
      missing_unchanged = before_after['before_presence'].to_i == 2 &&
                          before_after['before_guid'].nil?
      present_unchanged = positive_guid?(before_after['before_guid'])
      no_effect = [1, 2].include?(before_after['before_presence'].to_i) &&
                  before_after['before_presence'].to_i == before_after['after_presence'].to_i &&
                  before_after['before_guid'] == before_after['after_guid'] &&
                  (missing_unchanged || present_unchanged)
      compensated = rollback_after && created &&
                    rollback_after['before_presence'].to_i == 1 &&
                    rollback_after['after_presence'].to_i == 2 &&
                    rollback_after['before_guid'] == before_after['after_guid'] &&
                    rollback_after['after_guid'].nil?
      unchanged = rollback_after && no_effect &&
                  rollback_after['before_presence'] == before_after['before_presence'] &&
                  rollback_after['after_presence'] == before_after['after_presence'] &&
                  rollback_after['before_guid'] == before_after['before_guid'] &&
                  rollback_after['after_guid'] == before_after['after_guid']

      proved = case phase
               when 2
                 [!rollback, created, execute['state'].to_i == 1,
                  execute_status == 'ok', done == 1, status == 1].all?
               when 3
                 [rollback, compensated, [1, 2].include?(execute['state'].to_i),
                  rollback&.dig('state')&.to_i == 1, rollback_status == 'ok',
                  execute_status == (execute['state'].to_i == 1 ? 'ok' : 'failed'),
                  done == 2, status == 1].all?
               when 4
                 base = [no_effect, execute['state'].to_i == 2, execute_status == 'failed']
                 terminal = if rollback
                              [unchanged, rollback['state'].to_i == 1,
                               rollback_status == 'ok', done == 2, status == 1]
                            else
                              [done == 1, status == 0]
                            end
                 (base + terminal).all?
               else
                 false
               end
      raise Refused, 'strict snapshot terminal phase and receipt disagree' unless proved

      verify_attempt_digests!(execute, before_after, execute_status)
      verify_attempt_digests!(rollback, rollback_after, rollback_status) if rollback
    rescue JSON::ParserError, TypeError
      raise Refused, 'strict snapshot output is malformed'
    end
    private_class_method :prove_snapshot_phase!

    def self.verify_attempt_digests!(attempt, observation, status)
      before_digest = StorageMutationReceipt.strict_observation_digest(
        observation['before_presence'], observation['before_path_digest'],
        observation['before_guid'], observation['before_owner_fs_guid']
      )
      after_digest = StorageMutationReceipt.strict_observation_digest(
        observation['after_presence'], observation['after_path_digest'],
        observation['after_guid'], observation['after_owner_fs_guid']
      )
      receipt_digest = StorageMutationReceipt.strict_receipt_digest(
        attempt['direction'], status, before_digest, after_digest
      )
      raise Refused, 'strict snapshot receipt digest does not match observation' unless
        attempt['before_digest'] == before_digest &&
        attempt['after_digest'] == after_digest &&
        attempt['receipt_digest'] == receipt_digest
    end
    private_class_method :verify_attempt_digests!

    def self.positive_guid?(value)
      return false unless value

      if value.is_a?(Numeric)
        value > 0 && value == value.to_i
      else
        value.to_s.match?(/\A[0-9]+\z/) && value.to_i > 0
      end
    end
    private_class_method :positive_guid?
  end
end
