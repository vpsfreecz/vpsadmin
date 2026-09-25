require 'digest'
require 'json'
require 'timeout'
require 'nodectld/storage_effect_registry'
require 'nodectld/storage_mutation_receipt'
require 'nodectld/utils/system'
require 'nodectld/utils/zfs'

module NodeCtld
  # Test-only, bounded 5215 physical evidence. A started attempt is durable
  # before the handler can invoke ZFS. No old group state file is proof here.
  class StorageGroupSnapshotReceipt
    class BindingRefused < StandardError; end
    class UnsettledAttempt < StandardError; end

    MAX_MEMBERS = 32
    EMPTY_GRAPH_DIGEST = Digest::SHA256.hexdigest(JSON.generate([[], 0, false]))

    class Inventory
      include Utils::System
      include Utils::Zfs

      def observe(target)
        owner_path = target.fetch(:owner_path)
        path = target.fetch(:path)
        # Depth one includes this filesystem's snapshots without recursively
        # scanning descendant datasets. Each read has an explicit wall bound.
        listing = Timeout.timeout(60) do
          zfs(:list, '-H -t all -d 1 -o name,guid', owner_path).output
        end
        raise 'group snapshot inventory is too large' if listing.bytesize > 32 * 1024 * 1024

        rows = listing.lines.map { |line| line.strip.split("\t", 2) }
        raise 'group snapshot inventory is malformed' if rows.any? do |name, guid|
          name.to_s.empty? || !guid.to_s.match?(/\A\d+\z/)
        end

        owners = rows.select { |name, _guid| name == owner_path }
        snapshots = rows.select { |name, _guid| name == path }
        raise 'group snapshot owner or path is ambiguous' unless owners.one? && snapshots.length <= 1

        owner_guid = owners.first.last
        raise 'group snapshot owner changed' unless owner_guid == target.fetch(:owner_guid)

        if snapshots.empty?
          return { presence: :missing, path:, owner_guid:,
                   graph_digest: EMPTY_GRAPH_DIGEST, empty_dependencies: true }
        end

        raw = Timeout.timeout(60) do
          zfs(:get, '-H -p -o property,value clones,userrefs,defer_destroy', path).output
        end
        props = raw.lines.map { |line| line.strip.split("\t", 2) }
        raise 'group snapshot dependencies are incomplete' unless
          props.length == 3 && props.map(&:first) == %w[clones userrefs defer_destroy]

        clones = props[0][1]
        refs = props[1][1]
        deferred = props[2][1]
        raise 'group snapshot dependencies are malformed' unless
          clones && refs&.match?(/\A\d+\z/) && %w[on off].include?(deferred)

        clone_paths = clones == '-' ? [] : clones.split(',')
        raise 'group snapshot clone list is malformed' if clone_paths.any?(&:empty?)

        graph_data = [clone_paths.sort, refs.to_i, deferred == 'on']
        graph_digest = Digest::SHA256.hexdigest(JSON.generate(graph_data))
        { presence: :present, path:, guid: snapshots.first.last, owner_guid:,
          graph_digest:, empty_dependencies: clone_paths.empty? && refs.to_i == 0 && deferred == 'off' }
      end
    end

    attr_reader :id, :direction, :targets, :before, :after, :intent_id

    def initialize(guard, trans, params, direction, signed_input_digest:, inventory: Inventory.new,
                   prior_execute: nil)
      @guard = guard
      @trans = trans
      @params = params
      @direction = direction
      @signed_input_digest = signed_input_digest
      @inventory = inventory
      @prior_execute = prior_execute
    end

    def strict_preflight!
      Db.open do |db|
        db.transaction(restart: false) do |t|
          check_single_member!(t)
          intent = load_intent!(t)
          @targets = load_targets!(t, intent)
          check_attempts!(t, intent)
        end
      end
      # A physical read failure never proves absence. No handler is built yet.
      observed = observe_all!
      if direction == :execute
        raise BindingRefused, 'group target already exists' unless observed.all? do |item|
          item[:presence] == :missing
        end
      else
        verify_rollback_prestate!(observed)
      end
      @before = observed
      self
    end

    def strict_terminal_binding!(db)
      intent = load_intent!(db)
      @targets = load_targets!(db, intent)
      [intent, @targets]
    end

    def start!
      # Recheck both the catalog and the physical graph immediately before
      # inserting the durable started row. The effect follows this insert.
      strict_preflight!
      Db.open do |db|
        db.transaction(restart: false) do |t|
          check_single_member!(t)
          intent = load_intent!(t)
          @targets = load_targets!(t, intent)
          check_attempts!(t, intent)
          t.prepared(
            'INSERT INTO storage_mutation_attempts ' \
            '(storage_mutation_intent_id, command_key, attempt_number, direction, state, ' \
            'strict_dispatch_registry_version, strict_signed_input_digest, ' \
            'started_at, created_at, updated_at) VALUES (?, ?, 1, ?, 0, ?, ?, ' \
            'UTC_TIMESTAMP(), UTC_TIMESTAMP(), UTC_TIMESTAMP())',
            intent['id'], '5215', direction_number,
            StorageEffectRegistry::VERSION, @signed_input_digest
          )
          @id = t.insert_id
          @intent_id = intent['id']
          t.prepared(
            'UPDATE storage_mutation_intents SET phase = 1, updated_at = UTC_TIMESTAMP() WHERE id = ?',
            @intent_id
          )
        end
      end
      self
    end

    def observe_all!
      targets.map { |target| @inventory.observe(target) }
    end

    def observe_target!(target)
      @inventory.observe(target)
    end

    def finish!(db, status, before, after)
      raise 'group snapshot observation is incomplete' unless
        before.length == targets.length && after.length == targets.length

      before.zip(after, targets).each do |prior, current, target|
        raise 'group snapshot observation path changed' unless
          prior.fetch(:path) == target.fetch(:path) && current.fetch(:path) == target.fetch(:path)

        db.prepared(
          'INSERT INTO storage_mutation_target_observations ' \
          '(storage_mutation_attempt_id, storage_mutation_target_id, before_presence, ' \
          'after_presence, before_path_digest, after_path_digest, before_graph_digest, ' \
          'after_graph_digest, before_guid, after_guid, before_owner_fs_guid, ' \
          'after_owner_fs_guid, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ' \
          'UTC_TIMESTAMP(), UTC_TIMESTAMP())',
          id, target.fetch(:id), presence(prior), presence(current),
          Digest::SHA256.hexdigest(prior.fetch(:path)),
          Digest::SHA256.hexdigest(current.fetch(:path)),
          prior[:graph_digest], current[:graph_digest], prior[:guid], current[:guid],
          prior[:owner_guid], current[:owner_guid]
        )
      end
      before_digest = self.class.aggregate_digest(targets, before)
      after_digest = self.class.aggregate_digest(targets, after)
      receipt_digest = StorageMutationReceipt.strict_receipt_digest(
        direction_number, status, before_digest, after_digest
      )
      db.prepared(
        'UPDATE storage_mutation_attempts SET state = ?, before_digest = ?, ' \
        'after_digest = ?, receipt_digest = ?, finished_at = UTC_TIMESTAMP(), ' \
        'updated_at = UTC_TIMESTAMP() WHERE id = ? AND state = 0',
        %i[ok warning].include?(status) ? 1 : 2,
        before_digest, after_digest, receipt_digest, id
      )
    end

    def settle!(db, phase)
      db.prepared(
        'UPDATE storage_mutation_intents SET phase = ' \
        'CASE WHEN phase = 5 THEN 5 ELSE ? END, settled_at = UTC_TIMESTAMP(), ' \
        'updated_at = UTC_TIMESTAMP() WHERE id = ?', phase, intent_id
      )
      StorageMutationReceipt.quarantine_intent!(db, intent_id) if phase == 5
    end

    def self.aggregate_digest(targets, observations)
      Digest::SHA256.hexdigest(JSON.generate(targets.zip(observations).map do |target, item|
        [target.fetch(:id), presence_value(item), Digest::SHA256.hexdigest(item.fetch(:path)),
         item[:guid]&.to_i&.to_s, item[:owner_guid]&.to_i&.to_s, item[:graph_digest]]
      end))
    end

    def self.presence_value(item)
      { unknown: 0, present: 1, missing: 2 }.fetch(item[:presence], 0)
    end

    def self.created?(prior, current)
      prior[:presence] == :missing && current[:presence] == :present &&
        prior[:path] == current[:path] && prior[:owner_guid] == current[:owner_guid] &&
        current[:guid].to_s.match?(/\A[1-9]\d*\z/) && current[:empty_dependencies]
    end

    def self.same?(prior, current)
      prior == current && %i[present missing].include?(prior[:presence])
    end

    def self.compensated?(prior, current)
      prior[:presence] == :present && current[:presence] == :missing &&
        prior[:path] == current[:path] && prior[:owner_guid] == current[:owner_guid] &&
        prior[:empty_dependencies] && current[:empty_dependencies]
    end

    private

    def check_single_member!(db)
      chain = db.prepared(
        'SELECT size FROM transaction_chains WHERE id = ? FOR UPDATE',
        @trans['transaction_chain_id']
      ).get
      members = []
      db.prepared(
        'SELECT id, handle FROM transactions WHERE transaction_chain_id = ? ' \
        'ORDER BY id LIMIT 2 FOR UPDATE', @trans['transaction_chain_id']
      ).each { |row| members << row }
      raise BindingRefused, 'strict group requires a sole 5215 chain member' unless
        chain && chain['size'].to_i == 1 && members.length == 1 &&
        members.first['id'].to_i == @trans['id'].to_i && members.first['handle'].to_i == 5215
    end

    def load_intent!(db)
      raise BindingRefused, 'group guard version is unsupported' unless
        @guard['registry_version'] == StorageEffectRegistry::VERSION &&
        @guard['protocol_version'] == 1

      intent = db.prepared(
        'SELECT id, transaction_id, transaction_chain_id, node_catalog_id, ' \
        'manifest_digest, protocol_version, phase FROM storage_mutation_intents ' \
        'WHERE token = ? FOR UPDATE', @guard.fetch('token')
      ).get
      raise BindingRefused, 'group token does not match transaction' unless
        intent && intent['transaction_id'].to_i == @trans['id'].to_i &&
        intent['transaction_chain_id'].to_i == @trans['transaction_chain_id'].to_i &&
        intent['node_catalog_id'].to_i == @trans['node_id'].to_i &&
        intent['manifest_digest'] == @guard['manifest_digest'] &&
        intent['protocol_version'].to_i == 1
      raise UnsettledAttempt, 'group intent needs reconciliation' if intent['phase'].to_i == 5

      intent
    end

    def load_targets!(db, intent)
      rows = []
      db.prepared(<<~SQL, intent['id']).each { |row| rows << row }
        SELECT target.id, target.sequence, target.command_key, target.kind,
               target.storage_mutation_intent_scope_id, target.snapshot_in_pool_id,
               target.snapshot_in_pool_in_branch_id, target.storage_filesystem_identity_id,
               target.catalog_kind, target.catalog_id, target.expected_path,
               target.expected_guid, target.expected_owner_fs_guid,
               linked.storage_mutation_intent_id AS linked_intent_id,
               linked.expected_epoch AS linked_epoch,
               scope.scope_key, scope.pool_catalog_id, scope.pool_id AS scope_pool_id,
               scope.dataset_in_pool_catalog_id, scope.dataset_in_pool_id AS scope_dip_id,
               scope.mutation_epoch AS scope_epoch,
               sip.snapshot_id, sip.dataset_in_pool_id, dip.pool_id AS dip_pool_id,
               snapshot.name AS snapshot_name,
               dataset.full_name AS dataset_name, pool.node_id AS pool_node_id,
               pool.role AS pool_role, pool.filesystem AS pool_fs,
               owner.id AS owner_id, owner.zfs_path AS owner_path,
               owner.path_digest AS owner_path_digest, owner.zfs_guid AS owner_guid,
               owner.physical_presence AS owner_presence,
               owner.pool_id AS owner_pool_id, owner.node_id AS owner_node_id,
               owner.owner_pool_id AS owner_other_pool_id,
               owner.dataset_tree_id AS owner_tree_id, owner.branch_id AS owner_branch_id,
               owner.snapshot_in_pool_clone_id AS owner_clone_id
        FROM storage_mutation_targets target
        LEFT JOIN storage_mutation_intent_scopes linked
          ON linked.id = target.storage_mutation_intent_scope_id
        LEFT JOIN storage_integrity_scopes scope
          ON scope.id = linked.storage_integrity_scope_id
        LEFT JOIN snapshot_in_pools sip ON sip.id = target.snapshot_in_pool_id
        LEFT JOIN snapshots snapshot ON snapshot.id = sip.snapshot_id
        LEFT JOIN dataset_in_pools dip ON dip.id = sip.dataset_in_pool_id
        LEFT JOIN datasets dataset ON dataset.id = dip.dataset_id
        LEFT JOIN pools pool ON pool.id = dip.pool_id
        LEFT JOIN storage_filesystem_identities owner ON owner.dataset_in_pool_id = dip.id
        WHERE target.storage_mutation_intent_id = ? ORDER BY target.sequence LIMIT 34 FOR UPDATE
      SQL
      snapshots = @params.fetch('snapshots')
      raise BindingRefused, 'group target count is invalid' unless
        rows.length == snapshots.length + 1 && snapshots.length.between?(1, MAX_MEMBERS) &&
        rows.map { |row| row['sequence'].to_i } == (0..snapshots.length).to_a

      links = []
      db.prepared(
        'SELECT id FROM storage_mutation_intent_scopes WHERE storage_mutation_intent_id = ? LIMIT 34 FOR UPDATE',
        intent['id']
      ).each { |row| links << row['id'].to_i }
      raise BindingRefused, 'group scope links do not match targets' unless
        links.length == rows.length && links.sort == rows.map do |row|
          row['storage_mutation_intent_scope_id'].to_i
        end.sort

      pool_row = rows.first
      raise BindingRefused, 'group Pool observer target is malformed' unless
        pool_row['command_key'] == '5215' && pool_row['kind'] == 'observer_unbounded' &&
        pool_row['linked_intent_id'].to_i == intent['id'].to_i &&
        pool_row['linked_epoch'].to_i == pool_row['scope_epoch'].to_i &&
        %w[snapshot_in_pool_id snapshot_in_pool_in_branch_id storage_filesystem_identity_id
           catalog_kind catalog_id expected_path expected_guid expected_owner_fs_guid
           dataset_in_pool_catalog_id scope_dip_id].all? { |key| pool_row[key].nil? } &&
        pool_row['scope_key'] == "pool:#{pool_row['pool_catalog_id']}" &&
        pool_row['pool_catalog_id'].to_i == pool_row['scope_pool_id'].to_i

      pool_id = pool_row['pool_catalog_id'].to_i
      seen_dips = []
      targets = rows.drop(1).zip(snapshots).map do |row, snapshot|
        owner_path = "#{snapshot.fetch('pool_fs')}/#{snapshot.fetch('dataset_name')}"
        path = "#{owner_path}@#{@params.fetch('planned_snapshot_name')}"
        owner_guid = row['expected_owner_fs_guid']&.to_i&.to_s
        snapshot_name = row['snapshot_name'].to_s.delete_suffix(' (unconfirmed)')
        other_owner_links = %w[owner_other_pool_id owner_tree_id owner_branch_id owner_clone_id]
        raise BindingRefused, 'group DIP target or owner is malformed' unless
          row['command_key'] == '5215' && row['kind'] == 'snapshot_create' &&
          row['linked_intent_id'].to_i == intent['id'].to_i &&
          row['linked_epoch'].to_i == row['scope_epoch'].to_i &&
          row['snapshot_in_pool_id'] && row['snapshot_in_pool_in_branch_id'].nil? &&
          row['storage_filesystem_identity_id'].nil? &&
          row['catalog_kind'] == 'SnapshotInPool' &&
          row['catalog_id'].to_i == row['snapshot_in_pool_id'].to_i &&
          row['expected_guid'].nil? && row['expected_path'] == path &&
          row['snapshot_id'].to_i == snapshot.fetch('snapshot_id').to_i &&
          snapshot_name == @params.fetch('planned_snapshot_name') &&
          row['pool_fs'] == snapshot.fetch('pool_fs') &&
          row['dataset_name'] == snapshot.fetch('dataset_name') &&
          [0, 1].include?(row['pool_role'].to_i) &&
          row['dip_pool_id'].to_i == pool_id &&
          row['pool_node_id'].to_i == @trans['node_id'].to_i &&
          row['scope_key'] == "dip:#{row['dataset_in_pool_id']}" &&
          row['pool_catalog_id'].to_i == pool_id && row['scope_pool_id'].to_i == pool_id &&
          row['dataset_in_pool_catalog_id'].to_i == row['dataset_in_pool_id'].to_i &&
          row['scope_dip_id'].to_i == row['dataset_in_pool_id'].to_i &&
          owner_guid&.match?(/\A[1-9]\d*\z/) && row['owner_id'] &&
          row['owner_guid']&.to_i&.to_s == owner_guid &&
          row['owner_path'] == owner_path &&
          row['owner_path_digest'] == Digest::SHA256.hexdigest(owner_path) &&
          row['owner_presence'].to_i == 1 && row['owner_pool_id'].to_i == pool_id &&
          row['owner_node_id'].to_i == @trans['node_id'].to_i &&
          other_owner_links.all? { |key| row[key].nil? }

        seen_dips << row['dataset_in_pool_id'].to_i
        { id: row['id'].to_i, sip_id: row['snapshot_in_pool_id'].to_i,
          path:, owner_path:, owner_guid: }
      end
      raise BindingRefused, 'group DIPs or paths are duplicated' unless
        seen_dips.uniq.length == targets.length &&
        targets.map { |target| target[:path] }.uniq.length == targets.length &&
        targets.map { |target| target[:sip_id] } == targets.map { |target| target[:sip_id] }.sort

      targets
    end

    def check_attempts!(db, intent)
      rows = []
      db.prepared(
        'SELECT id, command_key, direction, state, strict_dispatch_registry_version, ' \
        'strict_signed_input_digest, before_digest, after_digest, receipt_digest, finished_at ' \
        'FROM storage_mutation_attempts WHERE storage_mutation_intent_id = ? LIMIT 3 FOR UPDATE',
        intent['id']
      ).each { |row| rows << row }
      if direction == :execute
        raise UnsettledAttempt, 'group already has an attempt' unless
          intent['phase'].to_i == 0 && rows.empty?

        return
      end

      if @prior_execute
        attempt, status, before, after = @prior_execute
        raise UnsettledAttempt, 'group partial execute is unproved' unless
          rows.length == 1 && rows.first['id'].to_i == attempt.id.to_i &&
          rows.first['direction'].to_i == 0 && rows.first['state'].to_i == 0 &&
          rows.first['strict_dispatch_registry_version'].to_i == StorageEffectRegistry::VERSION &&
          rows.first['strict_signed_input_digest'] == @signed_input_digest &&
          intent['phase'].to_i == 1 && status == :failed &&
          before.length == targets.length && after.length == targets.length &&
          before.all? { |item| item[:presence] == :missing } &&
          after.zip(before).all? do |item, prior|
            self.class.same?(prior, item) || self.class.created?(prior, item)
          end

        @created = after.map { |item| item[:presence] == :present ? item[:guid] : nil }
        return
      end

      execute = rows.first
      raise UnsettledAttempt, 'group rollback lacks exact execute proof' unless
        intent['phase'].to_i == 2 && rows.length == 1 && execute['command_key'] == '5215' &&
        execute['direction'].to_i == 0 && execute['state'].to_i == 1 &&
        execute['strict_dispatch_registry_version'].to_i == StorageEffectRegistry::VERSION &&
        execute['strict_signed_input_digest'] == @signed_input_digest &&
        execute['finished_at'] && execute['receipt_digest']

      @created = load_created_identities!(db, execute)
    end

    def load_created_identities!(db, execute)
      rows = []
      db.prepared(
        'SELECT storage_mutation_target_id, before_presence, after_presence, before_guid, ' \
        'after_guid, before_path_digest, after_path_digest, before_graph_digest, ' \
        'after_graph_digest, before_owner_fs_guid, after_owner_fs_guid ' \
        'FROM storage_mutation_target_observations WHERE storage_mutation_attempt_id = ? LIMIT 33',
        execute['id']
      ).each { |row| rows << row }
      raise UnsettledAttempt, 'group execute observations are incomplete' unless rows.length == targets.length

      identities = targets.map do |target|
        matches = rows.select { |row| row['storage_mutation_target_id'].to_i == target[:id] }
        row = matches.first
        raise UnsettledAttempt, 'group execute identity is unproved' unless
          matches.one? && row['before_presence'].to_i == 2 && row['after_presence'].to_i == 1 &&
          row['before_guid'].nil? && row['after_guid']&.to_i&.positive? &&
          row['before_path_digest'] == Digest::SHA256.hexdigest(target[:path]) &&
          row['after_path_digest'] == Digest::SHA256.hexdigest(target[:path]) &&
          row['before_owner_fs_guid']&.to_i&.to_s == target[:owner_guid] &&
          row['after_owner_fs_guid']&.to_i&.to_s == target[:owner_guid] &&
          row['before_graph_digest'] == EMPTY_GRAPH_DIGEST &&
          row['after_graph_digest'] == EMPTY_GRAPH_DIGEST

        row['after_guid'].to_i.to_s
      end
      before = targets.map do |target|
        { presence: :missing, path: target[:path], owner_guid: target[:owner_guid],
          graph_digest: EMPTY_GRAPH_DIGEST }
      end
      after = targets.zip(identities).map do |target, guid|
        { presence: :present, path: target[:path], owner_guid: target[:owner_guid], guid:,
          graph_digest: EMPTY_GRAPH_DIGEST }
      end
      raise UnsettledAttempt, 'group execute aggregate digest is unproved' unless
        execute['before_digest'] == self.class.aggregate_digest(targets, before) &&
        execute['after_digest'] == self.class.aggregate_digest(targets, after) &&
        execute['receipt_digest'] == StorageMutationReceipt.strict_receipt_digest(
          0, :ok, execute['before_digest'], execute['after_digest']
        )

      identities
    end

    def verify_rollback_prestate!(observed)
      raise UnsettledAttempt, 'group rollback physical identity changed' unless
        observed.zip(@created).all? do |item, guid|
          if guid
            item[:presence] == :present && item[:guid] == guid && item[:empty_dependencies]
          else
            item[:presence] == :missing && item[:empty_dependencies]
          end
        end
    end

    public

    def created_guids
      @created
    end

    def presence(item)
      self.class.presence_value(item)
    end

    def direction_number
      direction == :execute ? 0 : 1
    end
  end
end
