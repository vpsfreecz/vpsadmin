require 'digest'
require 'json'
require 'nodectld/storage_effect_registry'

module NodeCtld
  # The 5204 observer receipt correlates a guarded command with its staged intent.
  # A started row commits before ZFS runs, so a replay can refuse uncertainty.
  class StorageMutationReceipt
    class BindingRefused < StandardError; end
    class UnsettledAttempt < StandardError; end

    def self.strict_observation_digest(presence, path_digest, guid, owner_guid)
      values = [presence.to_i, path_digest, guid&.to_i&.to_s, owner_guid&.to_i&.to_s]
      Digest::SHA256.hexdigest(JSON.generate(values))
    end

    def self.strict_receipt_digest(direction, status, before_digest, after_digest)
      values = [direction.to_i, status.to_s, before_digest, after_digest]
      Digest::SHA256.hexdigest(JSON.generate(values))
    end

    def self.quarantine_guard!(db, guard, trans)
      row = db.prepared(
        'SELECT id FROM storage_mutation_intents WHERE token = ? ' \
        'AND transaction_id = ? AND node_catalog_id = ? FOR UPDATE',
        guard.fetch('token'), trans.fetch('id'), trans.fetch('node_id')
      ).get
      raise 'storage mutation intent cannot be quarantined' unless row

      quarantine_intent!(db, row['id'])
    end

    def self.quarantine_intent!(db, intent_id)
      db.prepared(
        'UPDATE storage_mutation_intents SET phase = 5, updated_at = UTC_TIMESTAMP() ' \
        'WHERE id = ?', intent_id
      )
      db.prepared(
        'UPDATE storage_integrity_scopes scope ' \
        'JOIN storage_mutation_intent_scopes linked ' \
        'ON linked.storage_integrity_scope_id = scope.id ' \
        'SET scope.state = 2, scope.updated_at = UTC_TIMESTAMP() ' \
        'WHERE linked.storage_mutation_intent_id = ?', intent_id
      )
    end

    attr_reader :id, :target_id, :direction, :expected_path, :expected_owner_guid

    def initialize(guard, trans, params, direction, strict: false,
                   strict_signed_input_digest: nil)
      @guard = guard
      @trans = trans
      @params = params
      @direction = direction
      @strict = strict
      @strict_signed_input_digest = strict_signed_input_digest
    end

    def strict_preflight!
      raise 'strict receipt validation was not requested' unless @strict

      validate_planned_name!

      Db.open do |db|
        db.transaction(restart: false) do |t|
          intent = load_intent!(t)
          target = strict_target!(t, intent)
          strict_attempts!(t, intent, target)
        end
      end
      self
    end

    # Rechecks the current catalog binding inside the final chain-close SQL
    # transaction. Terminal attempts are inspected separately by the caller.
    def strict_terminal_binding!(db)
      raise BindingRefused, 'strict receipt validation was not requested' unless @strict

      validate_planned_name!
      intent = load_intent!(db)
      [intent, strict_target!(db, intent)]
    end

    def start!
      validate_planned_name!
      verify_strict_signed_input! if @strict

      Db.open do |db|
        db.transaction(restart: false) do |t|
          intent = load_intent!(t)
          target = if @strict
                     strict_target!(t, intent).tap { |row| strict_attempts!(t, intent, row) }
                   else
                     t.prepared(
                       'SELECT target.id, sip.snapshot_id, target.expected_path, ' \
                       'target.expected_owner_fs_guid ' \
                       'FROM storage_mutation_targets target ' \
                       'JOIN snapshot_in_pools sip ON sip.id = target.snapshot_in_pool_id ' \
                       "WHERE target.storage_mutation_intent_id = ? AND target.command_key = '5204' " \
                       "AND target.kind = 'snapshot_create'",
                       intent['id']
                     ).get
                   end
          expected_path = "#{@params.fetch('pool_fs')}/#{@params.fetch('dataset_name')}@" \
                          "#{@params.fetch('planned_snapshot_name')}"
          unless target && target['snapshot_id'].to_i == @params.fetch('snapshot_id').to_i &&
                 target['expected_path'] == expected_path
            raise(@strict ? BindingRefused : RuntimeError,
                  'storage mutation target does not match snapshot')
          end

          prior = t.prepared(
            'SELECT id FROM storage_mutation_attempts ' \
            'WHERE storage_mutation_intent_id = ? AND command_key = ? AND direction = ? LIMIT 1',
            intent['id'], '5204', direction_number
          ).get
          if prior
            self.class.quarantine_intent!(t, intent['id'])
            @unsettled = true
            next
          end

          t.prepared(
            'INSERT INTO storage_mutation_attempts ' \
            '(storage_mutation_intent_id, command_key, attempt_number, direction, state, ' \
            'strict_dispatch_registry_version, strict_signed_input_digest, ' \
            'started_at, created_at, updated_at) VALUES (?, ?, 1, ?, 0, ?, ?, ' \
            'UTC_TIMESTAMP(), UTC_TIMESTAMP(), UTC_TIMESTAMP())',
            intent['id'], '5204', direction_number,
            @strict ? StorageEffectRegistry::VERSION : nil,
            @strict ? @strict_signed_input_digest : nil
          )
          @id = t.insert_id
          @target_id = target['id']
          @intent_id = intent['id']
          @expected_path = expected_path
          @expected_owner_guid = target['expected_owner_fs_guid']&.to_i&.to_s
          t.prepared(
            'UPDATE storage_mutation_intents SET phase = 1, updated_at = UTC_TIMESTAMP() WHERE id = ?',
            @intent_id
          )
        end
      end
      if @unsettled
        raise UnsettledAttempt, 'storage mutation attempt already exists; reconcile before retry'
      end

      self
    end

    def successful_execute_identity
      identity = nil
      Db.open do |db|
        row = db.prepared(
          'SELECT observation.after_guid, observation.after_owner_fs_guid, ' \
          'observation.after_path_digest FROM storage_mutation_attempts attempt ' \
          'JOIN storage_mutation_target_observations observation ' \
          'ON observation.storage_mutation_attempt_id = attempt.id ' \
          'WHERE attempt.storage_mutation_intent_id = ? AND attempt.command_key = ? ' \
          'AND attempt.direction = 0 AND attempt.state = 1 ' \
          'AND observation.before_presence = 2 AND observation.after_presence = 1 ' \
          'AND observation.before_owner_fs_guid = observation.after_owner_fs_guid ' \
          'AND observation.storage_mutation_target_id = ? ORDER BY attempt.id DESC LIMIT 1',
          @intent_id, '5204', @target_id
        ).get
        if row && row['after_guid'] && row['after_owner_fs_guid'] &&
           row['after_path_digest']
          identity = { guid: row['after_guid'].to_i.to_s,
                       owner_guid: row['after_owner_fs_guid'].to_i.to_s,
                       path_digest: row['after_path_digest'] }
        end
      end
      identity
    end

    def finish!(db, status, before, after)
      before ||= { presence: :unknown }
      after ||= { presence: :unknown }
      receipt = { direction:, status:, before:, after: }
      if @strict
        before_digest = self.class.strict_observation_digest(
          presence(before), path_digest(before), before[:guid], before[:owner_guid]
        )
        after_digest = self.class.strict_observation_digest(
          presence(after), path_digest(after), after[:guid], after[:owner_guid]
        )
        receipt_digest = self.class.strict_receipt_digest(
          direction_number, status, before_digest, after_digest
        )
      else
        before_digest = Digest::SHA256.hexdigest(JSON.generate(before))
        after_digest = Digest::SHA256.hexdigest(JSON.generate(after))
        receipt_digest = Digest::SHA256.hexdigest(JSON.generate(receipt))
      end
      db.prepared(
        'INSERT INTO storage_mutation_target_observations ' \
        '(storage_mutation_attempt_id, storage_mutation_target_id, before_presence, ' \
        'after_presence, before_path_digest, after_path_digest, before_guid, after_guid, ' \
        'before_owner_fs_guid, after_owner_fs_guid, created_at, updated_at) ' \
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, UTC_TIMESTAMP(), UTC_TIMESTAMP())',
        id, target_id, presence(before), presence(after), path_digest(before),
        path_digest(after), before[:guid], after[:guid], before[:owner_guid], after[:owner_guid]
      )
      db.prepared(
        'UPDATE storage_mutation_attempts SET state = ?, before_digest = ?, ' \
        'after_digest = ?, receipt_digest = ?, finished_at = UTC_TIMESTAMP(), ' \
        'updated_at = UTC_TIMESTAMP() WHERE id = ? AND state = 0',
        %i[ok warning].include?(status) ? 1 : 2, before_digest, after_digest,
        receipt_digest, id
      )
    end

    def settle!(db, phase)
      db.prepared(
        'UPDATE storage_mutation_intents SET phase = ' \
        'CASE WHEN phase = 5 THEN 5 ELSE ? END, settled_at = UTC_TIMESTAMP(), ' \
        'updated_at = UTC_TIMESTAMP() WHERE id = ?', phase, @intent_id
      )
      return unless phase == 5

      self.class.quarantine_intent!(db, @intent_id)
    end

    private

    def verify_strict_signed_input!
      require 'nodectld/storage_strict_dispatch'

      params, guard, digest = StorageStrictDispatch.signed_snapshot!(@trans)
      return if params == @params && guard == @guard &&
                digest == @strict_signed_input_digest

      raise BindingRefused, 'strict snapshot signed input differs from receipt'
    rescue StorageStrictDispatch::Refused => e
      raise BindingRefused, e.message
    end

    def validate_planned_name!
      return if @params.fetch('planned_snapshot_name').to_s.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\z/)

      raise BindingRefused, 'guarded snapshot has an invalid planned name'
    end

    def load_intent!(db)
      if @strict
        raise BindingRefused, 'strict snapshot guard version does not match node' unless
          @guard['registry_version'] == StorageEffectRegistry::VERSION
        raise BindingRefused, 'strict snapshot guard protocol is unsupported' unless @guard['protocol_version'] == 1
      end

      intent = db.prepared(
        'SELECT id, transaction_id, transaction_chain_id, node_catalog_id, ' \
        'manifest_digest, protocol_version, phase FROM storage_mutation_intents ' \
        'WHERE token = ? FOR UPDATE', @guard.fetch('token')
      ).get
      bound = intent && [
        intent['transaction_id'].to_i == @trans['id'].to_i,
        intent['node_catalog_id'].to_i == @trans['node_id'].to_i,
        intent['manifest_digest'] == @guard['manifest_digest'],
        intent['protocol_version'].to_i == @guard['protocol_version'].to_i
      ].all?
      raise BindingRefused, 'storage mutation token does not match command' unless bound
      raise UnsettledAttempt, 'storage mutation needs reconciliation' if intent['phase'].to_i == 5
      if @strict && intent['transaction_chain_id'].to_i != @trans['transaction_chain_id'].to_i
        raise BindingRefused, 'storage mutation chain does not match command'
      end

      intent
    end

    def strict_target!(db, intent)
      pool_target, snapshot_target, pool_scope, dip_scope = strict_manifest!(db, intent)
      rows = []
      db.prepared(<<~SQL, snapshot_target['id']).each { |row| rows << row }
        SELECT target.id, target.command_key, target.kind, target.expected_path,
               target.expected_owner_fs_guid, target.snapshot_in_pool_id,
               target.snapshot_in_pool_in_branch_id, sip.snapshot_id,
               sip.dataset_in_pool_id, dip.pool_id AS dip_pool_id,
               dataset.full_name AS dataset_full_name,
               pool.node_id AS pool_node_id, pool.role AS pool_role,
               pool.filesystem AS pool_fs,
               owner.id AS owner_id, owner.zfs_guid AS owner_guid,
               owner.zfs_path AS owner_path, owner.path_digest AS owner_path_digest,
               owner.pool_id AS owner_pool_id, owner.node_id AS owner_node_id,
               owner.physical_presence AS owner_presence,
               owner.owner_pool_id AS owner_other_pool_id,
               owner.dataset_tree_id AS owner_tree_id,
               owner.branch_id AS owner_branch_id,
               owner.snapshot_in_pool_clone_id AS owner_clone_id,
               linked.storage_mutation_intent_id AS linked_intent_id,
               scope.pool_catalog_id AS scope_pool_id,
               scope.dataset_in_pool_catalog_id AS scope_dip_id,
               scope.pool_id AS scope_live_pool_id,
               scope.dataset_in_pool_id AS scope_live_dip_id,
               scope.scope_key AS scope_key
        FROM storage_mutation_targets target
        LEFT JOIN snapshot_in_pools sip ON sip.id = target.snapshot_in_pool_id
        LEFT JOIN dataset_in_pools dip ON dip.id = sip.dataset_in_pool_id
        LEFT JOIN datasets dataset ON dataset.id = dip.dataset_id
        LEFT JOIN pools pool ON pool.id = dip.pool_id
        LEFT JOIN storage_filesystem_identities owner ON owner.dataset_in_pool_id = dip.id
        LEFT JOIN storage_mutation_intent_scopes linked
          ON linked.id = target.storage_mutation_intent_scope_id
        LEFT JOIN storage_integrity_scopes scope ON scope.id = linked.storage_integrity_scope_id
        WHERE target.id = ?
        LIMIT 2
      SQL
      raise BindingRefused, 'strict snapshot catalog join is not unique' unless rows.length == 1

      row = rows.first
      owner_path = "#{@params.fetch('pool_fs')}/#{@params.fetch('dataset_name')}"
      expected_path = "#{owner_path}@#{@params.fetch('planned_snapshot_name')}"
      expected_owner = row['expected_owner_fs_guid']&.to_i&.to_s
      raise BindingRefused, 'strict snapshot target is not an exact nonbackup DIP occurrence' unless
        row['command_key'] == '5204' && row['kind'] == 'snapshot_create' &&
        row['snapshot_in_pool_id'] && !row['snapshot_in_pool_in_branch_id'] &&
        [0, 1].include?(row['pool_role'].to_i) &&
        row['pool_node_id'].to_i == @trans['node_id'].to_i &&
        row['pool_fs'] == @params.fetch('pool_fs') &&
        row['dataset_full_name'] == @params.fetch('dataset_name') &&
        row['snapshot_id'].to_i == @params.fetch('snapshot_id').to_i &&
        row['expected_path'] == expected_path &&
        row['linked_intent_id'].to_i == intent['id'].to_i &&
        row['scope_pool_id'].to_i == row['dip_pool_id'].to_i &&
        row['scope_live_pool_id'].to_i == row['dip_pool_id'].to_i &&
        row['scope_dip_id'].to_i == row['dataset_in_pool_id'].to_i &&
        row['scope_live_dip_id'].to_i == row['dataset_in_pool_id'].to_i &&
        row['scope_key'] == "dip:#{row['dataset_in_pool_id']}" &&
        pool_target['storage_mutation_intent_scope_id'].to_i !=
        snapshot_target['storage_mutation_intent_scope_id'].to_i &&
        pool_scope['pool_catalog_id'].to_i == row['dip_pool_id'].to_i &&
        pool_scope['pool_id'].to_i == row['dip_pool_id'].to_i &&
        pool_scope['dataset_in_pool_catalog_id'].nil? &&
        pool_scope['dataset_in_pool_id'].nil? &&
        pool_scope['scope_key'] == "pool:#{row['dip_pool_id']}" &&
        dip_scope['pool_catalog_id'].to_i == row['dip_pool_id'].to_i &&
        dip_scope['pool_id'].to_i == row['dip_pool_id'].to_i &&
        dip_scope['dataset_in_pool_catalog_id'].to_i == row['dataset_in_pool_id'].to_i &&
        dip_scope['dataset_in_pool_id'].to_i == row['dataset_in_pool_id'].to_i &&
        dip_scope['scope_key'] == "dip:#{row['dataset_in_pool_id']}"
      raise BindingRefused, 'strict snapshot owner identity is incomplete or changed' unless
        expected_owner && expected_owner.to_i > 0 && row['owner_id'] &&
        row['owner_presence'].to_i == 1 &&
        row['owner_guid']&.to_i&.to_s == expected_owner &&
        row['owner_path'] == owner_path &&
        row['owner_path_digest'] == Digest::SHA256.hexdigest(owner_path) &&
        row['owner_pool_id'].to_i == row['dip_pool_id'].to_i &&
        row['owner_node_id'].to_i == @trans['node_id'].to_i &&
        row['owner_other_pool_id'].nil? && row['owner_tree_id'].nil? &&
        row['owner_branch_id'].nil? && row['owner_clone_id'].nil?

      row
    end

    def strict_manifest!(db, intent)
      targets = []
      db.prepared(
        'SELECT id, sequence, command_key, kind, storage_mutation_intent_scope_id, ' \
        'storage_filesystem_identity_id, snapshot_in_pool_id, ' \
        'snapshot_in_pool_in_branch_id, catalog_kind, catalog_id, expected_path, ' \
        'expected_guid, expected_owner_fs_guid FROM storage_mutation_targets ' \
        'WHERE storage_mutation_intent_id = ? ORDER BY sequence LIMIT 3 FOR UPDATE',
        intent['id']
      ).each { |row| targets << row }
      raise BindingRefused, 'strict snapshot requires its two exact targets' unless
        targets.length == 2 && targets.map { |row| row['sequence'].to_i } == [0, 1]

      pool_target, snapshot_target = targets
      raise BindingRefused, 'strict snapshot Pool observer target is malformed' unless
        pool_target['command_key'] == '5204' &&
        pool_target['kind'] == 'observer_unbounded' &&
        %w[storage_filesystem_identity_id snapshot_in_pool_id
           snapshot_in_pool_in_branch_id catalog_kind catalog_id expected_path
           expected_guid expected_owner_fs_guid].all? { |key| pool_target[key].nil? }
      raise BindingRefused, 'strict snapshot DIP target is malformed' unless
        snapshot_target['command_key'] == '5204' &&
        snapshot_target['kind'] == 'snapshot_create' &&
        snapshot_target['snapshot_in_pool_id'] &&
        snapshot_target['storage_filesystem_identity_id'].nil? &&
        snapshot_target['snapshot_in_pool_in_branch_id'].nil? &&
        snapshot_target['catalog_kind'] == 'SnapshotInPool' &&
        snapshot_target['catalog_id'].to_i == snapshot_target['snapshot_in_pool_id'].to_i &&
        snapshot_target['expected_guid'].nil? &&
        snapshot_target['expected_owner_fs_guid']&.to_i&.positive?

      links = []
      db.prepared(
        'SELECT id, storage_integrity_scope_id FROM storage_mutation_intent_scopes ' \
        'WHERE storage_mutation_intent_id = ? LIMIT 3 FOR UPDATE', intent['id']
      ).each { |row| links << row }
      link_ids = targets.map { |row| row['storage_mutation_intent_scope_id'].to_i }
      raise BindingRefused, 'strict snapshot requires its two exact scope links' unless
        links.length == 2 && link_ids.uniq.length == 2 &&
        links.map { |row| row['id'].to_i }.sort == link_ids.sort

      pool_link = links.find do |link|
        link['id'].to_i == pool_target['storage_mutation_intent_scope_id'].to_i
      end
      snapshot_link = links.find do |link|
        link['id'].to_i == snapshot_target['storage_mutation_intent_scope_id'].to_i
      end
      scope_query =
        'SELECT scope_key, pool_catalog_id, pool_id, dataset_in_pool_catalog_id, ' \
        'dataset_in_pool_id FROM storage_integrity_scopes WHERE id = ? FOR UPDATE'
      pool_scope = db.prepared(scope_query, pool_link['storage_integrity_scope_id']).get
      dip_scope = db.prepared(scope_query, snapshot_link['storage_integrity_scope_id']).get
      raise BindingRefused, 'strict snapshot scope is missing' unless pool_scope && dip_scope

      [pool_target, snapshot_target, pool_scope, dip_scope]
    end

    def strict_attempts!(db, intent, target)
      attempts = []
      db.prepared(
        'SELECT id, command_key, direction, state, before_digest, after_digest, ' \
        'receipt_digest, finished_at, ' \
        'strict_dispatch_registry_version, strict_signed_input_digest ' \
        'FROM storage_mutation_attempts WHERE storage_mutation_intent_id = ? LIMIT 2',
        intent['id']
      ).each { |row| attempts << row }
      if direction == :execute
        raise UnsettledAttempt, 'strict snapshot already has an attempt' unless
          intent['phase'].to_i == 0 && attempts.empty?

        return
      end

      raise UnsettledAttempt, 'strict rollback lacks one completed execute attempt' unless
        intent['phase'].to_i == 2 && attempts.length == 1 &&
        attempts.first['command_key'] == '5204' &&
        attempts.first['direction'].to_i == 0 && attempts.first['state'].to_i == 1 &&
        attempts.first['receipt_digest'] && attempts.first['finished_at'] &&
        attempts.first['strict_dispatch_registry_version'].to_i == StorageEffectRegistry::VERSION &&
        attempts.first['strict_signed_input_digest'] == @strict_signed_input_digest

      observations = []
      db.prepared(
        'SELECT before_presence, after_presence, before_guid, after_guid, ' \
        'before_owner_fs_guid, after_owner_fs_guid, before_path_digest, ' \
        'after_path_digest, storage_mutation_target_id ' \
        'FROM storage_mutation_target_observations ' \
        'WHERE storage_mutation_attempt_id = ? LIMIT 2', attempts.first['id']
      ).each { |row| observations << row }
      observation = observations.first
      expected_owner = target['expected_owner_fs_guid'].to_i.to_s
      digest = Digest::SHA256.hexdigest(target['expected_path'])
      raise UnsettledAttempt, 'strict rollback execute identity is unproved' unless
        observations.length == 1 && observation['storage_mutation_target_id'].to_i == target['id'].to_i &&
        observation['before_presence'].to_i == 2 && observation['after_presence'].to_i == 1 &&
        observation['before_guid'].nil? && observation['after_guid']&.to_i&.positive? &&
        observation['before_owner_fs_guid']&.to_i&.to_s == expected_owner &&
        observation['after_owner_fs_guid']&.to_i&.to_s == expected_owner &&
        observation['before_path_digest'] == digest && observation['after_path_digest'] == digest

      execute = attempts.first
      before_digest = self.class.strict_observation_digest(
        observation['before_presence'], observation['before_path_digest'],
        observation['before_guid'], observation['before_owner_fs_guid']
      )
      after_digest = self.class.strict_observation_digest(
        observation['after_presence'], observation['after_path_digest'],
        observation['after_guid'], observation['after_owner_fs_guid']
      )
      raise UnsettledAttempt, 'strict rollback execute receipt digest is unproved' unless
        execute['before_digest'] == before_digest && execute['after_digest'] == after_digest &&
        execute['receipt_digest'] == self.class.strict_receipt_digest(0, :ok, before_digest, after_digest)
    end

    def direction_number
      direction == :execute ? 0 : 1
    end

    def presence(value)
      { unknown: 0, present: 1, missing: 2 }.fetch(value[:presence], 0)
    end

    def path_digest(value)
      value[:path] && Digest::SHA256.hexdigest(value[:path])
    end
  end
end
