require 'json'
require 'time'

module VpsAdmin
  module StorageReconciler
    # Captures model rows from one explicit, read-only MariaDB snapshot.
    # The only raw SQL here controls the transaction and reads server metadata.
    class DbCapture
      class Incomplete < StandardError; end

      PAGE_SIZE = 1000
      PAYLOAD_PAGE_SIZE = 128
      MAX_SECONDS = 15 * 60
      MAX_ROWS = 300_000
      MAX_VISITED_ROWS = 300_000
      MAX_ARTIFACT_BYTES = 1024 * 1024 * 1024
      STATEMENT_SECONDS = 10
      MAX_TRANSACTION_OUTPUT_BYTES = 128 * 1024
      MAX_CHAIN_MEMBERS = 256
      MAX_GUID = (1 << 64) - 1
      GUID_COLUMNS = {
        'pools' => %w[zpool_guid],
        'snapshot_in_pools' => %w[zfs_guid zfs_owner_fs_guid],
        'snapshot_in_pool_in_branches' => %w[zfs_guid zfs_owner_fs_guid],
        'storage_filesystem_identities' => %w[zfs_guid],
        'storage_mutation_targets' => %w[expected_guid expected_owner_fs_guid],
        'storage_mutation_target_observations' => %w[
          before_guid after_guid before_owner_fs_guid after_owner_fs_guid
        ]
      }.freeze
      RESULT_STATUSES = { 0 => 'failed', 1 => 'ok', 2 => 'warning' }.freeze
      CONFIRMATION_TABLES = %w[
        pools datasets dataset_in_pools dataset_trees branches snapshots
        snapshot_in_pools snapshot_in_pool_in_branches snapshot_in_pool_clones
        storage_filesystem_identities exports mounts snapshot_downloads
      ].freeze
      POTENTIAL_RUNTIME_HANDLES = [1001, 1002, 1003, 2020].freeze

      attr_reader :summary, :ids

      def initialize(pool_id:, store:, now: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @pool_id = Integer(pool_id)
        @store = store
        @now = now
        @ids = Hash.new { |hash, key| hash[key] = Set.new }
        @written = Hash.new { |hash, key| hash[key] = Set.new }
        @queried_ids = Hash.new { |hash, key| hash[key] = Set.new }
        @expanded = Hash.new { |hash, key| hash[key] = Set.new }
        @transaction_results = {}
        @redacted_confirmations = Set.new
        @count = 0
        @visited = 0
        @bytes = 0
        @digest = Digest::SHA256.new
      end

      def capture!
        @started = @now.call
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          raise Incomplete, 'DB capture cannot join an existing transaction' if connection.transaction_open?

          original_timeout = connection.select_value('SELECT @@max_statement_time')
          connection.execute("SET SESSION max_statement_time = #{STATEMENT_SECONDS}")
          begin
            connection.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ')
            connection.execute('START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY')
            @connection = connection
            @connection_id = metadata!.fetch('connection_id')
            @observed_from_at = metadata!.fetch('server_time_utc')
            @store.write('db.jsonl') do |file|
              @file = file
              ActiveRecord::Base.uncached { capture_rows! }
              @observed_until_at = metadata!.fetch('server_time_utc')
              connection.execute('COMMIT')
            end
          rescue StandardError
            begin
              connection.execute('ROLLBACK')
            rescue StandardError
              nil
            end
            raise
          ensure
            begin
              connection.execute("SET SESSION max_statement_time = #{Float(original_timeout)}")
            rescue StandardError
              nil
            end
          end
        end
        selected_pool = @rows.fetch('pools').fetch(@pool_id)
        selected_zpool = selected_pool.fetch('filesystem').split('/').first
        managed_roots = @rows.fetch('pools').values.select do |row|
          row['node_id'] == selected_pool['node_id'] &&
            row.fetch('filesystem').split('/').first == selected_zpool
        end.map { |row| row.fetch('filesystem') }.sort
        @summary = {
          'version' => Format::VERSION, 'row_count' => @count,
          'digest' => @digest.hexdigest, 'connection_id' => @connection_id.to_s,
          'confirmation_coverage' => 'selected_chains_only',
          'historical_terminal_coverage' => 'unknown',
          'evidence_selection' => {
            'version' => 1, 'strategy' => 'current_graph_and_observable_node_work',
            'node_ids' => [selected_pool.fetch('node_id')],
            'catalog_closure' => 'complete', 'pending_snapshot_evidence' => 'complete',
            'observable_node_work' => 'complete', 'terminal_history' => 'not_enumerated'
          },
          'reference_closure' => 'selected_pool_sips_recursive_sipb_and_clones',
          'known_chain_overlap' => known_chain_overlap?,
          'scope_epoch' => @rows.fetch('storage_integrity_scopes', {}).values
                                .find { |row| row['scope_key'] == "pool:#{@pool_id}" }
                                &.fetch('mutation_epoch'),
          'freeze_epoch' => @rows.fetch('storage_freeze_controls').fetch(1).fetch('epoch'),
          'pool' => selected_pool.slice(
            'id', 'node_id', 'filesystem', 'zpool_guid', 'role'
          ),
          'managed_roots' => managed_roots,
          'observed_from_at' => @observed_from_at,
          'observed_until_at' => @observed_until_at
        }
      end

      private

      def metadata!
        row = @connection.select_one(
          'SELECT UTC_TIMESTAMP(6) AS server_time_utc, ' \
          'CONNECTION_ID() AS connection_id, @@tx_isolation AS isolation'
        )
        raise Incomplete, 'DB connection changed during capture' if
          @connection_id && row.fetch('connection_id').to_s != @connection_id.to_s
        raise Incomplete, 'DB isolation is not repeatable read' unless
          row.fetch('isolation').to_s.upcase.tr('_', '-') == 'REPEATABLE-READ'

        {
          'connection_id' => row.fetch('connection_id').to_s,
          'server_time_utc' => server_time(row.fetch('server_time_utc'))
        }
      end

      def server_time(value)
        return value.utc.iso8601(6) if value.respond_to?(:utc)

        "#{value.to_s.tr(' ', 'T')}Z"
      end

      def capture_rows!
        pool = Pool.unscoped.find(@pool_id)
        emit_ids(Pool, [pool.id])
        emit_relation(Pool, Pool.unscoped.where(node_id: pool.node_id))
        emit_ids(Node, [pool.node_id])
        emit_relation(DatasetInPool, DatasetInPool.unscoped.where(pool_id: pool.id))
        emit_ids(Dataset, ids_for(DatasetInPool).map { |id| @rows.fetch('dataset_in_pools').fetch(id)['dataset_id'] })
        capture_dataset_ancestors!
        emit_relation(DatasetTree, DatasetTree.unscoped.where(dataset_in_pool_id: ids_for(DatasetInPool)))
        emit_relation(Branch, Branch.unscoped.where(dataset_tree_id: ids_for(DatasetTree)))
        emit_relation(SnapshotInPool, SnapshotInPool.unscoped.where(dataset_in_pool_id: ids_for(DatasetInPool)))
        emit_ids(Snapshot, ids_for(SnapshotInPool).map { |id| @rows.fetch('snapshot_in_pools').fetch(id)['snapshot_id'] })
        capture_storage_closure!
        capture_dependents!
        emit_ids(StorageFreezeControl, [1])
        scope_keys = ["pool:#{@pool_id}"] + ids_for(DatasetInPool).map { |id| "dip:#{id}" }
        scope_keys.each_slice(PAGE_SIZE) do |slice|
          emit_relation(StorageIntegrityScope,
                        StorageIntegrityScope.unscoped.where(scope_key: slice))
        end
        capture_pending_snapshot_targets!
        capture_locks!
        capture_node_work!
        capture_node_owned_locks!
        capture_evidence_closure!
      end

      def capture_dataset_ancestors!
        ancestor_ids = @rows.fetch('datasets', {}).values.flat_map do |row|
          row['ancestry'].to_s.split('/').filter_map { |id| Integer(id, exception: false) }
        end
        emit_ids(Dataset, ancestor_ids)
      end

      def capture_sipb_closure!
        @sipb_inbound_scanned ||= Set.new
        frontier = ids_for(SnapshotInPoolInBranch) - @sipb_inbound_scanned.to_a
        100.times do
          break if frontier.empty?

          parent_ids = frontier.filter_map do |id|
            @rows.fetch('snapshot_in_pool_in_branches').fetch(id)['snapshot_in_pool_in_branch_id']
          end
          emit_ids(SnapshotInPoolInBranch, parent_ids)
          frontier.each_slice(PAGE_SIZE) do |slice|
            emit_relation(
              SnapshotInPoolInBranch,
              SnapshotInPoolInBranch.unscoped.where(snapshot_in_pool_in_branch_id: slice)
            )
          end
          @sipb_inbound_scanned.merge(frontier)
          frontier = ids_for(SnapshotInPoolInBranch).to_set
                                                    .difference(@sipb_inbound_scanned).to_a
        end
        raise Incomplete, 'SIPB reference closure is too deep' unless frontier.empty?
      end

      def capture_storage_closure!
        converged = false
        16.times do
          before = @count
          capture_sipb_closure!
          capture_related_hierarchy!
          frontier_ids_for(SnapshotInPool, :related_sips).each_slice(PAGE_SIZE) do |slice|
            emit_relation(SnapshotInPoolInBranch,
                          SnapshotInPoolInBranch.unscoped.where(snapshot_in_pool_id: slice))
            emit_relation(SnapshotInPoolClone,
                          SnapshotInPoolClone.unscoped.where(snapshot_in_pool_id: slice))
          end
          capture_filesystem_identities!
          if @count == before
            converged = true
            break
          end
        end
        raise Incomplete, 'storage dependency closure is too deep' unless
          converged && @sipb_inbound_scanned.superset?(ids_for(SnapshotInPoolInBranch).to_set)
      end

      def capture_related_hierarchy!
        emit_ids(
          SnapshotInPool,
          @rows.fetch('snapshot_in_pool_in_branches', {}).values.map { |row| row['snapshot_in_pool_id'] }
        )
        emit_ids(
          SnapshotInPool,
          @rows.fetch('snapshot_in_pool_clones', {}).values.map { |row| row['snapshot_in_pool_id'] }
        )
        emit_ids(
          Branch,
          @rows.fetch('snapshot_in_pool_in_branches', {}).values.map { |row| row['branch_id'] }
        )
        emit_ids(
          DatasetTree,
          @rows.fetch('branches', {}).values.map { |row| row['dataset_tree_id'] }
        )
        emit_ids(
          DatasetInPool,
          @rows.fetch('dataset_trees', {}).values.map { |row| row['dataset_in_pool_id'] }
        )
        emit_ids(
          Pool,
          @rows.fetch('dataset_in_pools', {}).values.map { |row| row['pool_id'] }
        )
        emit_ids(
          Dataset,
          @rows.fetch('dataset_in_pools', {}).values.map { |row| row['dataset_id'] }
        )
        capture_dataset_ancestors!
        emit_ids(
          Snapshot,
          @rows.fetch('snapshot_in_pools', {}).values.map { |row| row['snapshot_id'] }
        )
      end

      def capture_filesystem_identities!
        unless @scanned_selected_pool_fs
          emit_relation(StorageFilesystemIdentity,
                        StorageFilesystemIdentity.unscoped.where(pool_id: @pool_id))
          @scanned_selected_pool_fs = true
        end
        frontier_ids_for(SnapshotInPool, :filesystem_sips).each_slice(PAGE_SIZE) do |slice|
          emit_relation(
            StorageFilesystemIdentity,
            StorageFilesystemIdentity.unscoped.where(origin_snapshot_in_pool_id: slice)
          )
        end
        frontier_ids_for(SnapshotInPoolInBranch, :filesystem_sipbs).each_slice(PAGE_SIZE) do |slice|
          emit_relation(
            StorageFilesystemIdentity,
            StorageFilesystemIdentity.unscoped.where(origin_snapshot_in_pool_in_branch_id: slice)
          )
        end
        identities = @rows.fetch('storage_filesystem_identities', {}).values
        emit_ids(SnapshotInPool, identities.map { |row| row['origin_snapshot_in_pool_id'] })
        emit_ids(
          SnapshotInPoolInBranch,
          identities.map { |row| row['origin_snapshot_in_pool_in_branch_id'] }
        )
        emit_ids(Pool, identities.map { |row| row['owner_pool_id'] || row['pool_id'] })
        emit_ids(DatasetInPool, identities.map { |row| row['dataset_in_pool_id'] })
        emit_ids(DatasetTree, identities.map { |row| row['dataset_tree_id'] })
        emit_ids(Branch, identities.map { |row| row['branch_id'] })
        emit_ids(
          SnapshotInPoolClone,
          identities.map { |row| row['snapshot_in_pool_clone_id'] }
        )
      end

      def capture_dependents!
        emit_relation(Export, Export.unscoped.where(dataset_in_pool_id: ids_for(DatasetInPool)))
        emit_relation(Mount, Mount.unscoped.where(dataset_in_pool_id: ids_for(DatasetInPool)))
        emit_relation(Mount, Mount.unscoped.where(snapshot_in_pool_id: ids_for(SnapshotInPool)))
        emit_relation(
          Mount,
          Mount.unscoped.where(snapshot_in_pool_clone_id: ids_for(SnapshotInPoolClone))
        )
        emit_relation(
          SnapshotDownload,
          SnapshotDownload.unscoped.where(pool_id: @pool_id)
        )
        ids_for(Snapshot).each_slice(PAGE_SIZE) do |slice|
          emit_relation(
            SnapshotDownload,
            SnapshotDownload.unscoped.where(snapshot_id: slice)
          )
        end
      end

      def capture_pending_snapshot_targets!
        pending_sip_ids = @rows.fetch('snapshot_in_pools', {}).values.filter_map do |sip|
          snapshot = @rows.fetch('snapshots', {})[sip['snapshot_id'].to_i]
          sip.fetch('id') if sip['confirmed'].to_s != '1' ||
                             (snapshot && snapshot['confirmed'].to_s != '1')
        end.to_set
        sipbs = @rows.fetch('snapshot_in_pool_in_branches', {}).values
        sipbs.each do |sipb|
          pending_sip_ids << sipb['snapshot_in_pool_id'] if sipb['confirmed'].to_s != '1'
        end
        pending_sipb_ids = sipbs.filter_map do |sipb|
          sipb.fetch('id') if pending_sip_ids.include?(sipb['snapshot_in_pool_id'])
        end
        pending_targets_for!('SnapshotInPool', pending_sip_ids.to_a,
                             :snapshot_in_pool_id)
        pending_targets_for!('SnapshotInPoolInBranch', pending_sipb_ids,
                             :snapshot_in_pool_in_branch_id)
      end

      def pending_targets_for!(kind, ids, column)
        ids.each_slice(PAGE_SIZE) do |slice|
          emit_relation(StorageMutationTarget,
                        StorageMutationTarget.unscoped.where(column => slice))
          emit_relation(StorageMutationTarget,
                        StorageMutationTarget.unscoped.where(catalog_kind: kind, catalog_id: slice))
        end
      end

      def capture_node_work!
        node_id = @rows.fetch('pools').fetch(@pool_id).fetch('node_id')
        terminal_phases = %w[verified rolled_back failed settled_unverified]
                          .map { |name| StorageMutationIntent.phases.fetch(name) }
        [StorageMutationIntent.unscoped.where(node_catalog_id: node_id),
         StorageMutationIntent.unscoped.where(node_id:)].each do |relation|
          emit_relation(StorageMutationIntent, relation.where.not(phase: terminal_phases))
          attempt_states = %w[started uncertain].map do |name|
            StorageMutationAttempt.states.fetch(name)
          end
          attempts = StorageMutationAttempt.unscoped
                                           .where(state: attempt_states)
                                           .select(:storage_mutation_intent_id)
          emit_relation(StorageMutationIntent, relation.where(id: attempts))
        end

        active_states = %w[staged queued rollbacking fatal resolved]
                        .map { |name| TransactionChain.states.fetch(name) }
        active_chains = TransactionChain.unscoped.where(state: active_states).select(:id)
        emit_relation(Transaction, Transaction.unscoped.where(node_id:, transaction_chain_id: active_chains))
        emit_relation(Transaction, Transaction.unscoped.where(node_id:, done: 0)) do |row|
          potential_storage_transaction?(row)
        end
        pending = TransactionConfirmation.unscoped.where(done: 0).select(:transaction_id)
        emit_relation(Transaction, Transaction.unscoped.where(node_id:, id: pending))
      end

      def capture_node_owned_locks!
        node_id = @rows.fetch('pools').fetch(@pool_id).fetch('node_id').to_i
        pools = Pool.unscoped.where(node_id:).select(:id)
        dips = DatasetInPool.unscoped.where(pool_id: pools).select(:id)
        trees = DatasetTree.unscoped.where(dataset_in_pool_id: dips).select(:id)
        sips = SnapshotInPool.unscoped.where(dataset_in_pool_id: dips).select(:id)
        resources = {
          'Node' => node_id, 'Pool' => pools, 'DatasetInPool' => dips,
          'DatasetTree' => trees,
          'Branch' => Branch.unscoped.where(dataset_tree_id: trees).select(:id),
          'SnapshotInPool' => sips,
          'SnapshotInPoolInBranch' => SnapshotInPoolInBranch.unscoped.where(
            snapshot_in_pool_id: sips
          ).select(:id),
          'SnapshotInPoolClone' => SnapshotInPoolClone.unscoped.where(
            snapshot_in_pool_id: sips
          ).select(:id)
        }
        relation = ResourceLock.unscoped.where(
          "resource_locks.locked_by_type = 'TransactionChain' AND " \
          '(EXISTS (SELECT 1 FROM transactions t WHERE t.transaction_chain_id = ' \
          'resource_locks.locked_by_id AND t.node_id = ?) OR ' \
          'EXISTS (SELECT 1 FROM storage_mutation_intents i WHERE i.transaction_chain_id = ' \
          'resource_locks.locked_by_id AND (i.node_id = ? OR i.node_catalog_id = ?)))',
          node_id, node_id, node_id
        )
        resources.each do |resource, owners|
          relation = relation.or(ResourceLock.unscoped.where(resource:, row_id: owners))
        end
        emit_relation(ResourceLock, relation)
      end

      def capture_evidence_closure!
        converged = false
        16.times do
          before = @count
          capture_reached_intents!
          capture_reached_chains!
          capture_reached_intents!
          if @count == before
            converged = true
            break
          end
        end
        raise Incomplete, 'storage evidence closure is too deep' unless converged
      end

      def capture_reached_intents!
        emit_ids(StorageMutationIntent,
                 @rows.fetch('storage_mutation_targets', {}).values.map { |row| row['storage_mutation_intent_id'] })
        emit_ids(StorageMutationIntent,
                 @rows.fetch('storage_mutation_attempts', {}).values.map { |row| row['storage_mutation_intent_id'] })
        emit_ids(StorageMutationAttempt,
                 @rows.fetch('storage_mutation_target_observations', {}).values.map do |row|
                   row['storage_mutation_attempt_id']
                 end)
        emit_ids(StorageMutationTarget,
                 @rows.fetch('storage_mutation_target_observations', {}).values.map do |row|
                   row['storage_mutation_target_id']
                 end)
        emit_ids(StorageMutationIntentScope,
                 @rows.fetch('storage_mutation_targets', {}).values.map do |row|
                   row['storage_mutation_intent_scope_id']
                 end)
        emit_ids(StorageMutationIntent,
                 @rows.fetch('storage_mutation_intent_scopes', {}).values.map do |row|
                   row['storage_mutation_intent_id']
                 end)
        frontier_ids_for(StorageMutationIntent, :intent_evidence).each_slice(PAGE_SIZE) do |slice|
          emit_relation(StorageMutationIntentScope,
                        StorageMutationIntentScope.unscoped.where(storage_mutation_intent_id: slice))
          emit_relation(StorageMutationTarget,
                        StorageMutationTarget.unscoped.where(storage_mutation_intent_id: slice))
          emit_relation(StorageMutationAttempt,
                        StorageMutationAttempt.unscoped.where(storage_mutation_intent_id: slice))
        end
        emit_ids(StorageIntegrityScope,
                 @rows.fetch('storage_mutation_intent_scopes', {}).values.map do |row|
                   row['storage_integrity_scope_id']
                 end)
        frontier_ids_for(StorageMutationAttempt, :attempt_observations).each_slice(PAGE_SIZE) do |slice|
          emit_relation(StorageMutationTargetObservation,
                        StorageMutationTargetObservation.unscoped.where(storage_mutation_attempt_id: slice))
        end
        frontier_ids_for(StorageMutationTarget, :target_observations).each_slice(PAGE_SIZE) do |slice|
          emit_relation(StorageMutationTargetObservation,
                        StorageMutationTargetObservation.unscoped.where(storage_mutation_target_id: slice))
        end
      end

      def capture_reached_chains!
        intents = @rows.fetch('storage_mutation_intents', {}).values
        emit_ids(Transaction, intents.map { |row| row['transaction_id'] })
        chain_ids = intents.map { |row| row['transaction_chain_id'] }
        chain_ids.concat(@rows.fetch('transactions', {}).values.map { |row| row['transaction_chain_id'] })
        chain_ids.concat(@rows.fetch('resource_locks', {}).values.filter_map do |row|
          row['locked_by_id'] if row['locked_by_type'] == 'TransactionChain'
        end)
        emit_ids(TransactionChain, chain_ids)
        frontier_ids_for(TransactionChain, :chain_members).each_slice(PAGE_SIZE) do |slice|
          emit_relation(Transaction, Transaction.unscoped.where(transaction_chain_id: slice))
          emit_relation(StorageMutationIntent,
                        StorageMutationIntent.unscoped.where(transaction_chain_id: slice))
          emit_relation(ResourceLock,
                        ResourceLock.unscoped.where(locked_by_type: 'TransactionChain', locked_by_id: slice))
        end
        frontier_ids_for(Transaction, :transaction_confirmations).each_slice(PAGE_SIZE) do |slice|
          emit_relation(TransactionConfirmation,
                        TransactionConfirmation.unscoped.where(transaction_id: slice)) do |row|
            select_confirmation?(row)
          end
        end
      end

      def select_confirmation?(row)
        if CONFIRMATION_TABLES.include?(row.table_name)
          raw = row.attributes_before_type_cast['row_pks']
          raise Incomplete, 'confirmation row key exceeds capture bound' if
            raw.nil? || raw.bytesize > Format::MAX_RECORD_BYTES

          pk = row.row_pks
          return true if pk.is_a?(Hash) && pk['id'] && @ids[row.table_name].include?(pk['id'].to_i)
        end
        return false if row.done.to_i == 1

        @redacted_confirmations << row.id
        true
      rescue Psych::Exception, TypeError
        raise Incomplete, 'confirmation row key is invalid'
      end

      def capture_locks!
        %w[Node Pool DatasetInPool DatasetTree Branch Snapshot SnapshotInPool
           SnapshotInPoolInBranch SnapshotInPoolClone].each do |type|
          table = type.tableize
          ids_for_table(table).each_slice(PAGE_SIZE) do |slice|
            emit_relation(
              ResourceLock,
              ResourceLock.unscoped.where(resource: type, row_id: slice)
            )
          end
        end
        chain_ids = @rows.fetch('resource_locks', {}).values.filter_map do |row|
          row['locked_by_id'] if row['locked_by_type'] == 'TransactionChain'
        end
        emit_ids(TransactionChain, chain_ids)
        ids_for(TransactionChain).each_slice(PAGE_SIZE) do |slice|
          emit_relation(Transaction, Transaction.unscoped.where(transaction_chain_id: slice))
        end
      end

      def emit_ids(model, values)
        table = model.table_name
        pending = values.compact.map(&:to_i).uniq.reject do |id|
          @written[table].include?(id) || @queried_ids[table].include?(id)
        end
        @queried_ids[table].merge(pending)
        pending.each_slice(PAGE_SIZE) do |slice|
          emit_relation(model, model.unscoped.where(id: slice))
        end
      end

      def frontier_ids_for(model, key)
        known = @ids[model.table_name]
        frontier = known.difference(@expanded[key]).to_a
        @expanded[key].merge(frontier)
        frontier
      end

      def emit_relation(model, relation)
        table = model.table_name
        relation = bounded_projection(model, relation)
        page_size = [Transaction, TransactionConfirmation].include?(model) ? PAYLOAD_PAGE_SIZE : PAGE_SIZE
        last_id = 0
        loop do
          check_budget!
          page = relation.where(model.arel_table[:id].gt(last_id))
                         .reorder(id: :asc).limit(page_size).to_a
          @visited += page.size
          raise Incomplete, 'DB capture visited-row limit exceeded' if @visited > MAX_VISITED_ROWS
          break if page.empty?

          page.each do |row|
            last_id = row.id
            next if block_given? && !yield(row)
            next if @written[table].include?(row.id)

            write_record(model, row)
          end
          metadata!
        end
      end

      def bounded_projection(model, relation)
        case model.name
        when 'Transaction'
          columns = model.column_names - %w[input output signature]
          relation.select(*columns, Arel.sql("LEFT(transactions.output, #{MAX_TRANSACTION_OUTPUT_BYTES + 1}) AS output"))
        when 'TransactionConfirmation'
          columns = model.column_names - %w[attr_changes row_pks]
          expression = "LEFT(transaction_confirmations.row_pks, #{Format::MAX_RECORD_BYTES + 1}) AS row_pks"
          relation.select(*columns, Arel.sql(expression))
        else
          relation
        end
      end

      def write_record(model, row)
        raise Incomplete, 'DB capture row limit exceeded' if @count >= MAX_ROWS

        @rows ||= Hash.new { |hash, key| hash[key] = {} }
        table = model.table_name
        fields = row.attributes_before_type_cast
        GUID_COLUMNS.fetch(table, []).each do |column|
          next if fields[column].nil?

          fields = fields.merge(column => canonical_guid(fields[column], table:, column:))
        end
        # Transaction payloads can contain large signed input and unrelated
        # private command data. Correlation needs only indexed chain metadata.
        if model == Transaction
          @transaction_results[row.id] = terminal_transaction_result(fields)
          fields = fields.except('input', 'output', 'signature')
        elsif model == TransactionConfirmation && @redacted_confirmations.include?(row.id)
          fields = fields.except('row_pks', 'attr_changes')
        end
        fields = fields.transform_values { |value| normalize(value) }
        data = { 'table' => table, 'id' => row.id.to_s, 'fields' => fields }
        record = Format.record('db_object', data)
        line = "#{Format.canonical(record)}\n"
        raise Incomplete, 'oversize DB record' if line.bytesize > Format::MAX_RECORD_BYTES
        raise Incomplete, 'DB capture artifact-byte limit exceeded' if
          @bytes + line.bytesize > MAX_ARTIFACT_BYTES

        @file.write(line)
        @digest.update(line)
        @count += 1
        @bytes += line.bytesize
        @ids[table] << row.id
        @written[table] << row.id
        @rows[table][row.id] = fields
      end

      def known_chain_overlap?
        return true if @rows.fetch('resource_locks', {}).any?

        terminal_phases = %w[verified rolled_back failed settled_unverified]
                          .map { |name| StorageMutationIntent.phases.fetch(name).to_s }
        return true if @rows.fetch('storage_mutation_intents', {}).values.any? do |row|
          !terminal_phases.include?(row['phase'].to_s)
        end
        return true if @rows.fetch('storage_mutation_attempts', {}).values.any? do |row|
          %w[0 3].include?(row['state'].to_s)
        end

        transactions = @rows.fetch('transactions', {}).values
        return true if @rows.fetch('transaction_confirmations', {}).values.any? do |confirmation|
          confirmation['done'].to_s != '1'
        end

        members_by_chain = transactions.group_by do |row|
          Integer(row['transaction_chain_id'], exception: false)
        end
        transactions.any? do |row|
          next false unless potential_storage_transaction?(row)

          chain_id = Integer(row['transaction_chain_id'], exception: false)
          !proved_terminal_chain?(chain_id, members_by_chain)
        end
      end

      def potential_storage_transaction?(row)
        handle = Integer(row['handle'], exception: false)
        return true unless handle
        return true if POTENTIAL_RUNTIME_HANDLES.include?(handle)

        StorageEffectRegistry.fetch!(handle).admission_required
      rescue StorageEffectRegistry::Unclassified
        true
      end

      def proved_terminal_chain?(chain_id, members_by_chain)
        return false unless chain_id

        @proved_terminal_chains ||= {}
        return @proved_terminal_chains[chain_id] if @proved_terminal_chains.has_key?(chain_id)

        @proved_terminal_chains[chain_id] = terminal_chain_proof(chain_id, members_by_chain)
      end

      def terminal_chain_proof(chain_id, members_by_chain)
        chain = @rows.fetch('transaction_chains', {})[chain_id]
        return false unless chain

        state = Integer(chain['state'], exception: false)
        members = members_by_chain.fetch(chain_id, [])
        size = Integer(chain['size'], exception: false)
        return false unless size && size.between?(1, MAX_CHAIN_MEMBERS) && members.length == size
        return false unless members.all? { |member| @transaction_results[member['id'].to_i] }

        progress = Integer(chain['progress'], exception: false)
        case state
        when TransactionChain.states.fetch('done')
          return false unless progress == size

          members.all? do |member|
            result = @transaction_results[member['id'].to_i]
            !potential_storage_transaction?(member) ||
              (result[0] == 'execute' && %w[ok warning].include?(result[1]) && !result[2])
          end
        when TransactionChain.states.fetch('failed')
          return false unless progress == 0

          members.all? do |member|
            result = @transaction_results[member['id'].to_i]
            !potential_storage_transaction?(member) ||
              result == ['rollback', 'ok', false] || result == ['execute', 'failed', true]
          end
        else
          false
        end
      end

      def terminal_transaction_result(fields)
        done = Integer(fields['done'], exception: false)
        status = RESULT_STATUSES[Integer(fields['status'], exception: false)]
        finished_at = fields['finished_at']
        raw = fields['output']
        return unless [1, 2].include?(done) && status && finished_at &&
                      !finished_at.to_s.empty? && raw.is_a?(String) &&
                      raw.bytesize <= MAX_TRANSACTION_OUTPUT_BYTES

        output = JSON.parse(raw)
        direction = done == 2 ? 'rollback' : 'execute'
        result = output[direction] if output.is_a?(Hash)
        return unless result.is_a?(Hash) && result['status'] == status

        skipped = result['skipped'] == true
        return if result['skipped'] && !(direction == 'execute' && status == 'failed' && skipped)
        # A retry can leave started_at intact before fail_followers overwrites
        # the member with a skipped result. That result cannot prove no effect.
        return if skipped && !fields['started_at'].nil?

        [direction, status, skipped]
      rescue JSON::JSONError
        nil
      end

      def normalize(value)
        case value
        when Integer, BigDecimal
          value.to_s
        when Time, DateTime
          value.utc.iso8601(6)
        when Date
          value.iso8601
        else
          value
        end
      end

      def canonical_guid(value, table:, column:)
        raw = case value
              when BigDecimal then value.to_s('F')
              when Integer, String then value.to_s
              end
        invalid = "invalid GUID in #{table}.#{column}"
        raise Incomplete, invalid unless raw&.match?(/\A\d+(?:\.0+)?\z/)

        digits = raw.split('.').first.sub(/\A0+/, '')
        digits = '0' if digits.empty?
        raise Incomplete, invalid if digits.length > 20 || digits.to_i > MAX_GUID

        digits
      end

      def ids_for(model)
        ids_for_table(model.table_name)
      end

      def ids_for_table(table)
        @ids[table].to_a
      end

      def check_budget!
        raise Incomplete, 'DB capture row limit exceeded' if @count >= MAX_ROWS
        raise Incomplete, 'DB capture visited-row limit exceeded' if @visited > MAX_VISITED_ROWS
        raise Incomplete, 'DB capture artifact-byte limit exceeded' if @bytes > MAX_ARTIFACT_BYTES
        raise Incomplete, 'DB capture time limit exceeded' if @now.call - @started > MAX_SECONDS
      end
    end
  end
end
