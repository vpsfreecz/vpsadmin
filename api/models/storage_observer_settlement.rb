# frozen_string_literal: true

require 'json'

# Repairs only the observer journal lifecycle left prepared by an old NodeCtld.
# It does not establish physical identity or verify an integrity scope.
class StorageObserverSettlement
  MAX_CHAINS = 100
  MAX_TRANSACTIONS = 256
  STATUS_NAMES = { 0 => 'failed', 1 => 'ok', 2 => 'warning' }.freeze
  # Backup 5204 has only unbound observer targets. Its persisted command input
  # shape and unique backup Pool distinguish it from a damaged guarded intent.
  OPAQUE_SNAPSHOT_INTENT = <<~SQL.squish.freeze
    storage_mutation_intents.kind = 'snapshot_create'
    AND EXISTS (
      SELECT 1 FROM transactions t
      INNER JOIN transaction_chains chain ON chain.id = t.transaction_chain_id
      WHERE t.id = storage_mutation_intents.transaction_id AND t.handle = 5204
        AND storage_mutation_intents.transaction_chain_id = chain.id
        AND storage_mutation_intents.node_id = t.node_id
        AND storage_mutation_intents.node_catalog_id = t.node_id
        AND JSON_VALID(t.input) = 1
        AND BINARY JSON_TYPE(JSON_EXTRACT(IF(JSON_VALID(t.input), t.input, '{}'),
          '$.input')) = BINARY 'OBJECT'
        AND BINARY JSON_TYPE(JSON_EXTRACT(IF(JSON_VALID(t.input), t.input, '{}'),
          '$.input.pool_fs')) = BINARY 'STRING'
        AND JSON_CONTAINS_PATH(IF(JSON_VALID(t.input), t.input, '{}'),
          'one', '$.input.storage_guard') = 0
        AND EXISTS (
          SELECT 1 FROM storage_mutation_targets target
          INNER JOIN storage_mutation_intent_scopes linked
            ON linked.id = target.storage_mutation_intent_scope_id
            AND linked.storage_mutation_intent_id = storage_mutation_intents.id
          INNER JOIN storage_integrity_scopes scope
            ON scope.id = linked.storage_integrity_scope_id
          INNER JOIN pools pool ON pool.id = scope.pool_id
          WHERE target.storage_mutation_intent_id = storage_mutation_intents.id
            AND target.kind = 'observer_unbounded' AND target.command_key = '5204'
            AND scope.pool_catalog_id = pool.id
            AND scope.dataset_in_pool_id IS NULL
            AND scope.dataset_in_pool_catalog_id IS NULL
            AND pool.node_id = t.node_id AND pool.role = 2
            AND BINARY pool.filesystem = BINARY JSON_UNQUOTE(
              JSON_EXTRACT(IF(JSON_VALID(t.input), t.input, '{}'), '$.input.pool_fs'))
            AND (SELECT COUNT(*) FROM pools claimant
                 WHERE claimant.node_id = t.node_id
                   AND BINARY claimant.filesystem = BINARY pool.filesystem) = 1
        )
        AND NOT EXISTS (
          SELECT 1 FROM storage_mutation_targets target
          LEFT JOIN storage_mutation_intent_scopes linked
            ON linked.id = target.storage_mutation_intent_scope_id
          LEFT JOIN storage_integrity_scopes scope
            ON scope.id = linked.storage_integrity_scope_id
          LEFT JOIN pools pool ON pool.id = scope.pool_id
          WHERE target.storage_mutation_intent_id = storage_mutation_intents.id
            AND (target.kind != 'observer_unbounded' OR target.command_key != '5204'
              OR linked.id IS NULL OR linked.storage_mutation_intent_id != storage_mutation_intents.id
              OR scope.id IS NULL OR scope.pool_catalog_id != pool.id
              OR scope.dataset_in_pool_id IS NOT NULL
              OR scope.dataset_in_pool_catalog_id IS NOT NULL
              OR pool.id IS NULL OR pool.node_id != t.node_id
              OR target.storage_filesystem_identity_id IS NOT NULL
              OR target.snapshot_in_pool_id IS NOT NULL
              OR target.snapshot_in_pool_in_branch_id IS NOT NULL
              OR target.catalog_kind IS NOT NULL OR target.catalog_id IS NOT NULL
              OR target.expected_path IS NOT NULL OR target.expected_guid IS NOT NULL
              OR target.expected_owner_fs_guid IS NOT NULL)
        )
        AND NOT EXISTS (
          SELECT 1 FROM storage_mutation_intent_scopes linked
          LEFT JOIN storage_integrity_scopes scope
            ON scope.id = linked.storage_integrity_scope_id
          LEFT JOIN pools pool ON pool.id = scope.pool_id
          WHERE linked.storage_mutation_intent_id = storage_mutation_intents.id
            AND (scope.id IS NULL OR scope.pool_catalog_id != pool.id
              OR scope.dataset_in_pool_id IS NOT NULL
              OR scope.dataset_in_pool_catalog_id IS NOT NULL
              OR pool.id IS NULL OR pool.node_id != t.node_id
              OR (SELECT COUNT(*) FROM storage_mutation_targets target
                  WHERE target.storage_mutation_intent_id = storage_mutation_intents.id
                    AND target.storage_mutation_intent_scope_id = linked.id) != 1)
        )
    )
    AND NOT EXISTS (
      SELECT 1 FROM storage_mutation_attempts attempt
      WHERE attempt.storage_mutation_intent_id = storage_mutation_intents.id
    )
  SQL

  def self.generic_intents
    intents = StorageMutationIntent.unscoped
    ordinary = intents.where(transaction_id: Transaction.unscoped.where.not(handle: 5204).select(:id))
    opaque_snapshot = intents.where(OPAQUE_SNAPSHOT_INTENT)
    ordinary.or(opaque_snapshot)
  end
  private_class_method :generic_intents

  def self.catch_up!(limit: MAX_CHAINS, after_chain_id: 0, expected_epoch: nil)
    raise ArgumentError, 'invalid catch-up limit' unless limit.between?(1, MAX_CHAINS)
    raise ArgumentError, 'invalid chain cursor' unless after_chain_id.is_a?(Integer) &&
                                                       after_chain_id >= 0

    initial_control = StorageFreezeControl.singleton!
    raise ArgumentError, 'catch-up requires read-only mode' unless initial_control.read_only?

    expected_epoch ||= initial_control.epoch
    unless expected_epoch.is_a?(Integer) && expected_epoch >= 0
      raise ArgumentError, 'invalid catch-up freeze epoch'
    end
    raise ArgumentError, 'catch-up freeze epoch changed' unless initial_control.epoch == expected_epoch

    # Page every prepared intent, including malformed 5204 evidence that cannot
    # qualify for generic settlement. Otherwise catch-up can report an empty
    # page while a DB drain blocker is still present.
    page = StorageMutationIntent.unscoped.where(phase: :prepared)
                                .where('transaction_chain_id > ?', after_chain_id)
                                .distinct.order(:transaction_chain_id)
                                .limit(limit + 1)
                                .pluck(:transaction_chain_id)
    chain_ids = page.first(limit)
    settled = 0
    settled_chain_ids = []
    blocked_ids = []
    blocked_reasons = {}

    chain_ids.each do |chain_id|
      changed, reason = TransactionChain.transaction(requires_new: true) do
        control = StorageFreezeControl.lock.find(1)
        raise ArgumentError, 'catch-up requires read-only mode' unless control.read_only?
        raise ArgumentError, 'catch-up freeze epoch changed' unless control.epoch == expected_epoch

        chain = TransactionChain.lock.find_by(id: chain_id)
        blocker = chain ? proof_blocker(chain) : 'missing_chain'
        next [0, blocker] if blocker

        updated = generic_intents.where(transaction_chain_id: chain_id, phase: :prepared)
                                 .update_all(phase: 6, settled_at: Time.current,
                                             settlement_provenance: 'api_legacy_catch_up',
                                             updated_at: Time.current)
        [updated, updated > 0 ? nil : 'cas_no_change']
      end
      if changed > 0
        settled += changed
        settled_chain_ids << chain_id
      else
        blocked_ids << chain_id
        blocked_reasons[chain_id] = reason
      end
    end

    { scanned_chains: chain_ids.length, settled_intents: settled,
      settled_chain_ids:,
      blocked_chains: blocked_ids.length, blocked_chain_ids: blocked_ids,
      blocked_reasons:,
      after_chain_id:, next_after_chain_id: chain_ids.last,
      has_more: page.length > limit, limit: }
  end

  def self.proof_blocker(chain)
    return 'chain_not_terminal' unless %w[done failed].include?(chain.state)
    return 'oversized_chain' if chain.size > MAX_TRANSACTIONS
    return 'invalid_chain_size' unless chain[:size] >= 1

    transactions = Transaction.unscoped.where(transaction_chain_id: chain.id)
                              .order(:id).limit(MAX_TRANSACTIONS + 1).to_a
    return 'transaction_count_mismatch' unless transactions.length == chain.size

    transaction_ids = transactions.map(&:id)
    return 'transaction_result_incomplete' unless transactions.all? { |transaction| final_transaction?(transaction) }

    pending_confirmations = TransactionConfirmation.unscoped.where(
      transaction_id: transaction_ids, done: 0
    )
    return 'pending_confirmation' if pending_confirmations.exists?

    intents = StorageMutationIntent.unscoped.where(transaction_chain_id: chain.id)
    return 'unsettled_intent' if intents.where(phase: %i[executing needs_reconcile]).exists?
    return 'unsettled_attempt' if StorageMutationAttempt.unscoped
                                                        .where(storage_mutation_intent_id: intents.select(:id),
                                                               state: %i[started uncertain]).exists?

    generic_ids = generic_intents.where(transaction_chain_id: chain.id).pluck(:id).to_h do |id|
      [id, true]
    end
    transactions_by_id = transactions.index_by(&:id)
    return 'intent_link_or_physical_phase_unresolved' unless intents.all? do |intent|
      transaction = transactions_by_id[intent.transaction_id]
      transaction && (transaction.handle != 5204 ||
        %w[verified rolled_back failed settled_unverified].include?(intent.phase) ||
        generic_ids[intent.id])
    end

    nil
  end
  private_class_method :proof_blocker

  def self.final_transaction?(transaction)
    done = transaction.done_before_type_cast.to_i
    status = STATUS_NAMES[transaction.status.to_i]
    return false unless [1, 2].include?(done) && status && transaction.finished_at

    output = JSON.parse(transaction.output.to_s)
    return false unless output.is_a?(Hash)

    direction = done == 2 ? 'rollback' : 'execute'
    result = output[direction]
    return false unless result.is_a?(Hash) && result['status'] == status
    return true unless result['skipped']

    direction == 'execute' && status == 'failed' && result['skipped'] == true
  rescue JSON::ParserError
    false
  end
  private_class_method :final_transaction?
end
