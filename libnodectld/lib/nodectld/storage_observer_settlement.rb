require 'json'

module NodeCtld
  # A terminal chain result is control-flow evidence, not physical proof.
  class StorageObserverSettlement
    STATUS_NAMES = { 0 => 'failed', 1 => 'ok', 2 => 'warning' }.freeze
    FINAL_DONE = [1, 2].freeze
    FINAL_CHAIN = [2, 4].freeze
    MAX_TRANSACTIONS = 256
    # Backup snapshot creates have only unbound observer targets. The command
    # input and unique backup Pool distinguish them from damaged guarded work.
    OPAQUE_SNAPSHOT_INTENT = <<~SQL.freeze
      i.kind = 'snapshot_create'
      AND i.transaction_chain_id = t.transaction_chain_id
      AND i.node_id = t.node_id AND i.node_catalog_id = t.node_id
      AND EXISTS (SELECT 1 FROM transaction_chains chain WHERE chain.id = t.transaction_chain_id)
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
          AND linked.storage_mutation_intent_id = i.id
        INNER JOIN storage_integrity_scopes scope
          ON scope.id = linked.storage_integrity_scope_id
        INNER JOIN pools pool ON pool.id = scope.pool_id
        WHERE target.storage_mutation_intent_id = i.id
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
        WHERE target.storage_mutation_intent_id = i.id
          AND (target.kind != 'observer_unbounded' OR target.command_key != '5204'
            OR linked.id IS NULL OR linked.storage_mutation_intent_id != i.id
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
        WHERE linked.storage_mutation_intent_id = i.id
          AND (scope.id IS NULL OR scope.pool_catalog_id != pool.id
            OR scope.dataset_in_pool_id IS NOT NULL
            OR scope.dataset_in_pool_catalog_id IS NOT NULL
            OR pool.id IS NULL OR pool.node_id != t.node_id
            OR (SELECT COUNT(*) FROM storage_mutation_targets target
                WHERE target.storage_mutation_intent_id = i.id
                  AND target.storage_mutation_intent_scope_id = linked.id) != 1)
      )
      AND NOT EXISTS (
        SELECT 1 FROM storage_mutation_attempts attempt
        WHERE attempt.storage_mutation_intent_id = i.id
      )
    SQL
    GENERIC_INTENT = <<~SQL.freeze
      (t.handle != 5204 OR
        (t.handle = 5204 AND #{OPAQUE_SNAPSHOT_INTENT}))
    SQL

    def self.settle_chain!(db, chain_id)
      return unless generic_intent?(db, chain_id)
      return unless final_chain?(db, chain_id)
      return unless final_transactions?(db, chain_id)
      return if pending_confirmations?(db, chain_id)
      return if unsettled_physical_attempt?(db, chain_id)

      db.prepared(<<~SQL, 'node_chain_close', chain_id)
        UPDATE storage_mutation_intents i
        INNER JOIN transactions t ON t.id = i.transaction_id
        SET i.phase = 6, i.settled_at = UTC_TIMESTAMP(),
            i.settlement_provenance = ?
        WHERE i.transaction_chain_id = ? AND i.phase = 0 AND #{GENERIC_INTENT}
      SQL
    end

    def self.generic_intent?(db, chain_id)
      db.prepared(<<~SQL, chain_id).get
        SELECT i.id FROM storage_mutation_intents i
        INNER JOIN transactions t ON t.id = i.transaction_id
        WHERE i.transaction_chain_id = ? AND i.phase = 0 AND #{GENERIC_INTENT}
        LIMIT 1
      SQL
    end
    private_class_method :generic_intent?

    def self.final_chain?(db, chain_id)
      chain = db.prepared(
        'SELECT state, size FROM transaction_chains WHERE id = ?', chain_id
      ).get
      chain && FINAL_CHAIN.include?(chain['state'].to_i)
    end
    private_class_method :final_chain?

    def self.final_transactions?(db, chain_id)
      chain = db.prepared('SELECT size FROM transaction_chains WHERE id = ?', chain_id).get
      return false unless chain
      return false unless chain['size'].to_i.between?(1, MAX_TRANSACTIONS)

      rows = []
      db.prepared(
        'SELECT done, status, output, finished_at FROM transactions
         WHERE transaction_chain_id = ? ORDER BY id LIMIT ?',
        chain_id, MAX_TRANSACTIONS + 1
      ).each { |row| rows << row }
      return false unless rows.length == chain['size'].to_i

      rows.all? { |row| final_transaction?(row) }
    end
    private_class_method :final_transactions?

    def self.final_transaction?(row)
      done = row['done'].to_i
      status = STATUS_NAMES[row['status'].to_i]
      return false unless FINAL_DONE.include?(done) && status && row['finished_at']

      output = JSON.parse(row['output'].to_s)
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

    def self.pending_confirmations?(db, chain_id)
      db.prepared(
        'SELECT c.id FROM transaction_confirmations c
         INNER JOIN transactions t ON t.id = c.transaction_id
         WHERE t.transaction_chain_id = ? AND c.done = 0 LIMIT 1', chain_id
      ).get
    end
    private_class_method :pending_confirmations?

    def self.unsettled_physical_attempt?(db, chain_id)
      return true if db.prepared(
        'SELECT a.id FROM storage_mutation_attempts a
         INNER JOIN storage_mutation_intents i ON i.id = a.storage_mutation_intent_id
         WHERE i.transaction_chain_id = ? AND a.state IN (0, 3) LIMIT 1', chain_id
      ).get

      db.prepared(<<~SQL, chain_id).get
        SELECT i.id FROM storage_mutation_intents i
        LEFT JOIN transactions t ON t.id = i.transaction_id
        WHERE i.transaction_chain_id = ? AND
              (i.phase IN (1, 5) OR
                (i.phase = 0 AND
                  (t.id IS NULL OR t.transaction_chain_id != i.transaction_chain_id OR
                    (t.handle = 5204 AND NOT COALESCE((#{OPAQUE_SNAPSHOT_INTENT}), FALSE)))))
        LIMIT 1
      SQL
    end
    private_class_method :unsettled_physical_attempt?
  end
end
