require 'time'

module VpsAdmin
  module StorageReconciler
    # Captures model rows from one explicit, read-only MariaDB snapshot.
    # The only raw SQL here controls the transaction and reads server metadata.
    class DbCapture
      class Incomplete < StandardError; end

      PAGE_SIZE = 1000
      MAX_SECONDS = 15 * 60
      MAX_ROWS = 300_000
      STATEMENT_SECONDS = 10
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
        @count = 0
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
          'reference_closure' => 'selected_pool_sips_recursive_sipb_and_clones',
          'known_chain_overlap' => @rows.fetch('transactions', {}).values.any? do |row|
            [0, 2].include?(row['done'].to_i) &&
              (POTENTIAL_RUNTIME_HANDLES.include?(row['handle'].to_i) ||
                Transaction.for_type(row['handle'].to_i)&.storage_effect)
          end,
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
        emit_relation(
          SnapshotInPoolInBranch,
          SnapshotInPoolInBranch.unscoped.where(snapshot_in_pool_id: ids_for(SnapshotInPool))
        )
        capture_storage_closure!
        capture_dependents!
        emit_ids(StorageFreezeControl, [1])
        emit_relation(
          StorageIntegrityScope,
          StorageIntegrityScope.unscoped.where(pool_catalog_id: @pool_id)
        )
        capture_locks!
        capture_confirmations_and_chains!
        capture_mutation_evidence!
        capture_confirmations_and_chains!
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
          emit_relation(
            SnapshotInPoolClone,
            SnapshotInPoolClone.unscoped.where(snapshot_in_pool_id: ids_for(SnapshotInPool))
          )
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
        emit_relation(
          StorageFilesystemIdentity,
          StorageFilesystemIdentity.unscoped.where(pool_id: @pool_id)
        )
        ids_for(SnapshotInPool).each_slice(PAGE_SIZE) do |slice|
          emit_relation(
            StorageFilesystemIdentity,
            StorageFilesystemIdentity.unscoped.where(origin_snapshot_in_pool_id: slice)
          )
        end
        ids_for(SnapshotInPoolInBranch).each_slice(PAGE_SIZE) do |slice|
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

      def capture_confirmations_and_chains!
        # row_pks is serialized YAML without a searchable index. Scan only
        # confirmations belonging to unfinished node chains or chains already
        # bound to selected locks/intents. The transaction_id index bounds this.
        emit_relation(
          Transaction,
          Transaction.unscoped.where(
            node_id: @rows.fetch('pools').fetch(@pool_id)['node_id'], done: [0, 2]
          )
        ) do |row|
          klass = Transaction.for_type(row.handle)
          POTENTIAL_RUNTIME_HANDLES.include?(row.handle) || (klass && klass.storage_effect)
        end
        chain_ids = @rows.fetch('transactions', {}).values.map { |row| row['transaction_chain_id'] }
        emit_ids(TransactionChain, chain_ids)
        ids_for(TransactionChain).each_slice(PAGE_SIZE) do |slice|
          emit_relation(Transaction, Transaction.unscoped.where(transaction_chain_id: slice))
        end
        ids_for(Transaction).each_slice(PAGE_SIZE) do |slice|
          emit_relation(
            TransactionConfirmation,
            TransactionConfirmation.unscoped.where(transaction_id: slice)
          ) do |row|
            next false unless CONFIRMATION_TABLES.include?(row.table_name)

            pk = row.row_pks
            pk.is_a?(Hash) && pk['id'] && @ids[row.table_name].include?(pk['id'].to_i)
          end
        end
      end

      def capture_mutation_evidence!
        scope_ids = ids_for(StorageIntegrityScope)
        emit_relation(
          StorageMutationIntentScope,
          StorageMutationIntentScope.unscoped.where(storage_integrity_scope_id: scope_ids)
        )
        emit_relation(
          StorageMutationIntent,
          StorageMutationIntent.unscoped.where(transaction_chain_id: ids_for(TransactionChain))
        )
        emit_ids(
          StorageMutationIntent,
          @rows.fetch('storage_mutation_intent_scopes', {}).values.map { |row| row['storage_mutation_intent_id'] }
        )
        emit_ids(
          TransactionChain,
          @rows.fetch('storage_mutation_intents', {}).values.map { |row| row['transaction_chain_id'] }
        )
        emit_relation(
          StorageMutationIntentScope,
          StorageMutationIntentScope.unscoped.where(storage_mutation_intent_id: ids_for(StorageMutationIntent))
        )
        emit_relation(
          StorageMutationTarget,
          StorageMutationTarget.unscoped.where(storage_mutation_intent_id: ids_for(StorageMutationIntent))
        )
        emit_relation(
          StorageMutationAttempt,
          StorageMutationAttempt.unscoped.where(storage_mutation_intent_id: ids_for(StorageMutationIntent))
        )
        emit_relation(
          StorageMutationTargetObservation,
          StorageMutationTargetObservation.unscoped.where(
            storage_mutation_attempt_id: ids_for(StorageMutationAttempt)
          )
        )
      end

      def capture_locks!
        %w[Pool DatasetInPool DatasetTree Branch Snapshot SnapshotInPool
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
        values.compact.map(&:to_i).uniq.each_slice(PAGE_SIZE) do |slice|
          emit_relation(model, model.unscoped.where(id: slice))
        end
      end

      def emit_relation(model, relation)
        table = model.table_name
        last_id = 0
        loop do
          check_budget!
          page = relation.where(model.arel_table[:id].gt(last_id))
                         .reorder(id: :asc).limit(PAGE_SIZE).to_a
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

      def write_record(model, row)
        raise Incomplete, 'DB capture row limit exceeded' if @count >= MAX_ROWS

        @rows ||= Hash.new { |hash, key| hash[key] = {} }
        table = model.table_name
        fields = row.attributes_before_type_cast
        # Transaction payloads can contain large signed input and unrelated
        # private command data. Correlation needs only indexed chain metadata.
        fields = fields.except('input', 'output', 'signature') if model == Transaction
        fields = fields.transform_values { |value| normalize(value) }
        data = { 'table' => table, 'id' => row.id.to_s, 'fields' => fields }
        record = Format.record('db_object', data)
        line = "#{Format.canonical(record)}\n"
        raise Incomplete, 'oversize DB record' if line.bytesize > Format::MAX_RECORD_BYTES

        @file.write(line)
        @digest.update(line)
        @count += 1
        @ids[table] << row.id
        @written[table] << row.id
        @rows[table][row.id] = fields
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

      def ids_for(model)
        ids_for_table(model.table_name)
      end

      def ids_for_table(table)
        @ids[table].to_a
      end

      def check_budget!
        raise Incomplete, 'DB capture row limit exceeded' if @count >= MAX_ROWS
        raise Incomplete, 'DB capture time limit exceeded' if @now.call - @started > MAX_SECONDS
      end
    end
  end
end
