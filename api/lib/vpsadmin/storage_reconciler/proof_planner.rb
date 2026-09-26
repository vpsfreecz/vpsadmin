module VpsAdmin
  module StorageReconciler
    # Builds private, non-executable proposals from an already verified report.
    class ProofPlanner
      class Invalid < StandardError; end

      COVERAGE_BLOCKERS = %w[
        selected_chain_confirmations_only observer_epoch_without_freeze
        strict_writer_and_drain_proof_absent historical_terminal_coverage_unknown
      ].freeze
      CATALOG_OWNERS = {
        'owner_pool_id' => 'Pool',
        'dataset_in_pool_id' => 'DatasetInPool',
        'dataset_tree_id' => 'DatasetTree',
        'branch_id' => 'Branch',
        'snapshot_in_pool_clone_id' => 'SnapshotInPoolClone'
      }.freeze
      CATALOG_OWNERS_TABLE = {
        'Pool' => 'pools', 'DatasetInPool' => 'dataset_in_pools',
        'DatasetTree' => 'dataset_trees', 'Branch' => 'branches',
        'SnapshotInPoolClone' => 'snapshot_in_pool_clones'
      }.freeze

      def initialize(db_records:, zfs_records:, findings:, manifest:, report:, store:)
        @manifest = manifest
        @report = report
        @store = store
        @findings = findings
        finding_keys = findings.map do |record|
          Format.verify_record!(record, expected_kind: 'finding')
          record.fetch('fields').fetch('finding_key')
        end
        raise Invalid, 'duplicate finding key' unless finding_keys.uniq.length == finding_keys.length

        @db = Hash.new { |hash, key| hash[key] = {} }
        db_records.each do |record|
          Format.verify_record!(record, expected_kind: 'db_object')
          fields = record.fetch('fields')
          table = fields.fetch('table')
          id = fields.fetch('id').to_s
          raise Invalid, 'duplicate catalog row' if @db[table].has_key?(id)

          @db[table][id] = fields.fetch('fields')
        end
        @zfs = {}
        zfs_records.each do |record|
          Format.verify_record!(record, expected_kind: 'zfs_object')
          fields = record.fetch('fields')
          raise Invalid, 'duplicate physical path' if @zfs.has_key?(fields.fetch('path'))

          @zfs[fields.fetch('path')] = fields
        end
      end

      def actions
        raise Invalid, 'two-pass inventory proof is incomplete' unless two_pass_complete?

        @findings.map { |finding| action_for(finding.fetch('fields')) }
                 .sort_by do |action|
          fields = action.fetch('fields')
          [fields.fetch('finding_key'), fields['possible_operation'].to_s,
           fields['target_kind'].to_s, fields['target_id'].to_s]
        end
      end

      private

      def row(table, id)
        @db[table][id.to_s]
      end

      def action_for(finding)
        proposal = case finding.fetch('code')
                   when 'reciprocal_clone_origin_unrepresented' then origin_proposal(finding)
                   when 'legacy_identity_unverified'
                     snapshot_proposal(finding) || filesystem_proposal(finding)
                   end
        operation = proposal && proposal.fetch(:operation)
        finding_blockers = finding.fetch('blockers')
        if operation == 'set_filesystem_origin'
          finding_blockers -= %w[unique_catalog_source_unproved
                                 historical_promotion_proof_not_captured]
        end
        blockers = (finding_blockers + COVERAGE_BLOCKERS +
                    (proposal ? ['fresh_frozen_graph_required'] : class_blockers(finding))).uniq.sort
        before = proposal && proposal.fetch(:before)
        after = proposal && proposal.fetch(:after)
        preconditions = proposal ? proposal.fetch(:preconditions).sort_by { |item| Format.canonical(item) } : []
        dependencies = proposal ? proposal.fetch(:dependencies) : []
        if %w[create_filesystem_identity set_filesystem_origin].include?(operation)
          blockers = (blockers + ['full_node_identity_claims_not_captured']).sort
        end
        target_kind = proposal ? proposal.fetch(:target_kind) : catalog_target_kind(finding)
        target_id = if proposal
                      proposal.fetch(:target_id)
                    elsif target_kind
                      finding['subject_id']
                    end
        before_digest = before && @store.hmac(before)
        after_digest = after && @store.hmac(after)
        fields = {
          'plan_policy_version' => Format::PLAN_POLICY_VERSION,
          'finding_key' => finding.fetch('finding_key'),
          'finding_code' => finding.fetch('code'),
          'evidence_digest' => finding.fetch('evidence_digest'),
          'disposition' => proposal ? 'blocked_candidate' : 'no_action',
          'possible_operation' => operation,
          'target_kind' => target_kind, 'target_id' => target_id,
          'owner_kind' => proposal && proposal[:owner_kind],
          'owner_id' => proposal && proposal[:owner_id],
          'before_values' => before, 'after_values' => after,
          'before_digest' => before_digest, 'after_digest' => after_digest,
          'preconditions' => preconditions, 'dependencies' => dependencies,
          'precondition_digest' => @store.hmac(preconditions),
          'dependency_digest' => @store.hmac(dependencies),
          'proof_blockers' => blockers,
          'capture_digest' => @manifest.fetch('digest'),
          'report_digest' => @report.fetch('digest'),
          'key_id' => @store.key_id,
          'proof_coverage' => {
            'db_closure' => 'selected_pool_and_captured_dependencies',
            'historical_confirmations' => @manifest.dig('db', 'confirmation_coverage'),
            'historical_terminal_coverage' => @manifest.dig('db', 'historical_terminal_coverage'),
            'evidence_selection' => @manifest.dig('db', 'evidence_selection'),
            'node_inventory' => if two_pass_complete?
                                  'complete_manifest_two_pass'
                                else
                                  'two_pass_proof_missing'
                                end,
            'mutation_epoch' => @manifest.dig('scope', 'mutation_epoch'),
            'freeze_drain' => 'absent', 'strict_writer' => 'absent'
          },
          'executable' => false
        }
        action_key_material = [
          Format::PLAN_POLICY_VERSION, @manifest.fetch('run_id'),
          fields.fetch('finding_key'), fields.fetch('evidence_digest'),
          operation, target_kind, target_id,
          fields['owner_kind'], fields['owner_id'],
          before_digest, after_digest,
          fields.fetch('precondition_digest'),
          fields.fetch('dependency_digest'),
          fields.fetch('capture_digest'), fields.fetch('report_digest')
        ]
        fields['action_key'] = @store.hmac(action_key_material)
        Format.record('candidate_action', fields)
      end

      def class_blockers(finding)
        case finding.fetch('code')
        when 'disk_only_object', 'pending_snapshot_possible_pair_unresolved'
          %w[no_catalog_target no_import_or_destroy]
        when 'db_only_branch'
          %w[completed_destroy_lineage_missing full_dependency_closure_missing]
        when /\Areference_count_/
          %w[exact_reference_count_semantics_unproved]
        when 'sipb_parent_unresolved'
          %w[logical_parent_lineage_missing]
        when 'pending_dataset_create'
          %w[completed_chain_and_descendant_proof_missing]
        when 'headless_backup_dip'
          %w[detachment_lineage_missing]
        when 'pending_snapshot_path_unresolved'
          %w[signed_command_not_captured unsettled_snapshot_identity]
        else
          %w[unique_physical_and_catalog_proof_missing]
        end
      end

      def catalog_target_kind(finding)
        kind = finding['subject_kind']
        kind if %w[Pool DatasetInPool DatasetTree Branch Dataset SnapshotInPool
                   SnapshotInPoolInBranch SnapshotInPoolClone].include?(kind)
      end

      def legacy_finding(kind, id)
        @legacy_findings ||= @findings.filter_map do |record|
          fields = record.fetch('fields')
          [[fields['subject_kind'], fields['subject_id'].to_s], fields] if
            fields['code'] == 'legacy_identity_unverified'
        end.to_h
        @legacy_findings[[kind, id.to_s]]
      end

      def two_pass_complete?
        zfs = @manifest.fetch('zfs')
        first = zfs['first']
        second = zfs['second']
        managed_root = @manifest.dig('scope', 'managed_root')
        return false unless first.is_a?(Hash) && second.is_a?(Hash) &&
                            first['roots'].is_a?(Hash)

        return false unless first['roots'] == second['roots'] &&
                            first['roots'].keys.sort == @manifest.dig('db', 'managed_roots')&.sort &&
                            first['roots'][managed_root].to_s != ''

        roots_match = first['roots'].all? do |path, guid|
          @zfs.dig(path, 'type') == 'filesystem' && @zfs.dig(path, 'guid').to_s == guid.to_s
        end
        return false unless roots_match

        catalog_zpool_guid = @manifest.dig('db', 'pool', 'zpool_guid')
        first['zpool_guid'].to_s != '' && first['zpool_guid'] == second['zpool_guid'] &&
          (!catalog_zpool_guid || first['zpool_guid'].to_s == catalog_zpool_guid.to_s) &&
          zfs['digest'].to_s.match?(/\A[0-9a-f]{64}\z/) &&
          first['digest'] == zfs['digest'] && second['digest'] == zfs['digest'] &&
          first['count'].to_i == zfs['row_count'].to_i &&
          second['count'].to_i == zfs['row_count'].to_i
      end

      def unsettled_effect?(path, kind, id, sip_id: nil)
        unless @unsettled_target_paths
          @unsettled_target_paths = Set.new
          @unsettled_catalog_targets = Set.new
          active = @db['storage_mutation_intents'].filter_map do |intent_id, intent|
            intent_id if intent['node_catalog_id'].to_s ==
                         @manifest.dig('scope', 'node_id').to_s &&
                         %w[0 1 5].include?(intent['phase'].to_s)
          end.to_set
          @unsettled_active_node = active.any?
          @db['storage_mutation_targets'].each_value do |target|
            next unless active.include?(target['storage_mutation_intent_id'].to_s)

            @unsettled_target_paths << target['expected_path'] if target['expected_path']
            @unsettled_catalog_targets << [target['catalog_kind'], target['catalog_id'].to_s]
          end
        end
        @unsettled_active_node || @unsettled_target_paths.include?(path) ||
          @unsettled_catalog_targets.include?([kind, id.to_s]) ||
          (sip_id && @unsettled_catalog_targets.include?(['SnapshotInPool', sip_id.to_s]))
      end

      def snapshot_proposal(finding)
        kind = finding['subject_kind']
        return unless %w[SnapshotInPool SnapshotInPoolInBranch].include?(kind)
        return unless two_pass_complete?

        id = finding.fetch('subject_id')
        table = kind == 'SnapshotInPool' ? 'snapshot_in_pools' : 'snapshot_in_pool_in_branches'
        occurrence = row(table, id)
        path, pool, sip_id = snapshot_catalog_path(kind, id, occurrence)
        return unless path && pool && pool['id'].to_s == @manifest.dig('scope', 'pool_id').to_s
        return unless unique_snapshot_claim?(kind, id, path, pool)
        return unless %w[zfs_path zfs_guid zfs_owner_fs_guid].all? do |column|
          occurrence[column].nil?
        end
        return unless [nil, '0'].include?(occurrence['physical_presence'])
        return if unsettled_effect?(path, kind, id, sip_id:)

        physical = @zfs[path]
        return unless exact_snapshot?(physical, path)

        before = %w[zfs_path zfs_guid zfs_owner_fs_guid physical_presence]
                 .to_h { |column| [column, occurrence[column]] }
        after = { 'zfs_path' => path, 'zfs_guid' => physical['guid'].to_s,
                  'zfs_owner_fs_guid' => physical['owner_guid'].to_s,
                  'physical_presence' => '1' }
        preconditions = [catalog_precondition(table, id, occurrence),
                         { 'kind' => 'physical_snapshot', 'digest' => @store.hmac(physical) }]
        { operation: 'backfill_snapshot_occurrence_identity', target_kind: kind,
          target_id: id, before:, after:, preconditions:, dependencies: [] }
      end

      def snapshot_catalog_path(kind, id, occurrence)
        return unless occurrence

        sip = if kind == 'SnapshotInPool'
                occurrence
              else
                row('snapshot_in_pools', occurrence['snapshot_in_pool_id'])
              end
        dip = sip && row('dataset_in_pools', sip['dataset_in_pool_id'])
        pool = dip && row('pools', dip['pool_id'])
        snapshot = sip && row('snapshots', sip['snapshot_id'])
        return unless pool && snapshot && pool['node_id'].to_s ==
                                          @manifest.dig('scope', 'node_id').to_s

        if kind == 'SnapshotInPool'
          return if pool['role'].to_s == '2'

          base = catalog_owner_path('DatasetInPool', sip['dataset_in_pool_id'], pool)
        else
          return unless pool['role'].to_s == '2'

          branch = row('branches', occurrence['branch_id'])
          tree = branch && row('dataset_trees', branch['dataset_tree_id'])
          return unless tree && tree['dataset_in_pool_id'].to_s == dip['id'].to_s

          base = catalog_owner_path('Branch', occurrence['branch_id'], pool)
        end
        return unless base

        ["#{base}@#{snapshot.fetch('name')}", pool,
         kind == 'SnapshotInPool' ? id : sip['id']]
      end

      def unique_snapshot_claim?(kind, id, path, pool)
        return false if overlapping_other_pool?(path, pool)

        index_snapshot_occurrences!
        @snapshot_claims[[pool['id'].to_s, path]] == [[kind, id.to_s]]
      end

      def index_snapshot_occurrences!
        return if @snapshot_claims_indexed

        @snapshot_claims = Hash.new { |hash, key| hash[key] = [] }
        @source_rows_by_pool_path = Hash.new { |hash, key| hash[key] = [] }
        { 'SnapshotInPool' => 'snapshot_in_pools',
          'SnapshotInPoolInBranch' => 'snapshot_in_pool_in_branches' }.each do |kind, table|
          @db[table].each do |id, occurrence|
            expected = snapshot_catalog_path(kind, id, occurrence)
            next unless expected

            key = [expected[1]['id'].to_s, expected[0]]
            @snapshot_claims[key] << [kind, id]
            @source_rows_by_pool_path[key] << [kind, id, occurrence]
          end
        end
        @snapshot_claims_indexed = true
      end

      def index_filesystem_identities!
        return if @filesystem_identities_indexed

        @filesystem_identities_by_node_path = Hash.new { |hash, key| hash[key] = [] }
        @filesystem_identities_by_owner = Hash.new { |hash, key| hash[key] = [] }
        @filesystem_identities_by_node_digest = Hash.new { |hash, key| hash[key] = [] }
        @db['storage_filesystem_identities'].each do |id, identity|
          entry = [id, identity]
          path = identity['zfs_path']
          if identity['node_id'] && path
            @filesystem_identities_by_node_path[[identity['node_id'].to_s, path]] << entry
          end
          if identity['node_id'] && identity['path_digest']
            key = [identity['node_id'].to_s, identity['path_digest']]
            @filesystem_identities_by_node_digest[key] << entry
          end
          CATALOG_OWNERS.each do |column, kind|
            owner_id = identity[column]
            @filesystem_identities_by_owner[[kind, owner_id.to_s]] << entry if owner_id
          end
        end
        @filesystem_identities_indexed = true
      end

      def filesystem_identity_claims(kind, id, node_id, path)
        index_filesystem_identities!
        (@filesystem_identities_by_owner[[kind, id.to_s]] +
         @filesystem_identities_by_node_path[[node_id.to_s, path]])
          .uniq { |identity_id, _identity| identity_id }
      end

      def conflicting_node_digest_claim?(node_id, path, exclude_id: nil)
        index_filesystem_identities!
        digest = Digest::SHA256.hexdigest(path.b)
        @filesystem_identities_by_node_digest[[node_id.to_s, digest]].any? do |id, identity|
          id != exclude_id.to_s && identity['zfs_path'] != path
        end
      end

      def exact_snapshot?(physical, path)
        return false unless physical && physical['type'] == 'snapshot' &&
                            physical['path'] == path && physical['guid'] &&
                            physical['owner_guid'] &&
                            physical['owner_path'] == path.split('@', 2).first

        owner = @zfs[physical['owner_path']]
        index_filesystem_identities!
        owner_claims = @filesystem_identities_by_node_path[
          [@manifest.dig('scope', 'node_id').to_s, physical['owner_path']]
        ]
        owner && owner['type'] == 'filesystem' &&
          owner['guid'].to_s == physical['owner_guid'].to_s &&
          owner_claims.length <= 1 && owner_claims.none? do |_id, identity|
            identity['zfs_guid'] && identity['zfs_guid'].to_s != owner['guid'].to_s
          end
      end

      def filesystem_proposal(finding)
        kind = finding['subject_kind']
        return unless CATALOG_OWNERS.has_value?(kind) && two_pass_complete?

        id = finding.fetch('subject_id')
        pool = row('pools', @manifest.dig('scope', 'pool_id'))
        return unless pool && pool['node_id'].to_s == @manifest.dig('scope', 'node_id').to_s

        path = catalog_owner_path(kind, id, pool)
        physical = path && @zfs[path]
        return unless physical && physical['type'] == 'filesystem' && physical['guid'] &&
                      unique_catalog_path_claim?(kind, id, path, pool)
        return if unsettled_effect?(path, kind, id)

        column = CATALOG_OWNERS.key(kind)
        path_digest = Digest::SHA256.hexdigest(path.b)
        return if conflicting_node_digest_claim?(pool['node_id'], path)

        matches = filesystem_identity_claims(kind, id, pool['node_id'], path)
        return if matches.length > 1

        after = { 'node_id' => pool.fetch('node_id').to_s,
                  'pool_id' => pool.fetch('id').to_s, column => id.to_s,
                  'zfs_path' => path, 'path_digest' => path_digest,
                  'zfs_guid' => physical.fetch('guid').to_s,
                  'physical_presence' => '1', 'origin_state' => '0' }
        preconditions = [catalog_precondition(CATALOG_OWNERS_TABLE.fetch(kind), id,
                                              row(CATALOG_OWNERS_TABLE.fetch(kind), id)),
                         { 'kind' => 'physical_filesystem', 'digest' => @store.hmac(physical) }]
        if matches.empty?
          preconditions.concat(identity_claim_preconditions(kind, id, pool, path))
          { operation: 'create_filesystem_identity', target_kind: nil, target_id: nil,
            owner_kind: kind, owner_id: id, before: nil, after:,
            preconditions:, dependencies: [] }
        else
          identity_id, identity = matches.first
          return unless single_owner_fk?(identity, kind, id) &&
                        identity['pool_id'].to_s == pool['id'].to_s &&
                        identity['node_id'].to_s == pool['node_id'].to_s &&
                        [nil, path].include?(identity['zfs_path']) &&
                        [nil, path_digest].include?(identity['path_digest']) &&
                        identity['zfs_guid'].nil? &&
                        [nil, '0'].include?(identity['physical_presence']) &&
                        identity['origin_state'].to_s == '0' &&
                        identity['origin_snapshot_in_pool_id'].nil? &&
                        identity['origin_snapshot_in_pool_in_branch_id'].nil?

          before = after.keys.to_h { |field| [field, identity[field]] }
          preconditions << catalog_precondition('storage_filesystem_identities', identity_id,
                                                identity)
          { operation: 'backfill_filesystem_identity',
            target_kind: 'StorageFilesystemIdentity', target_id: identity_id,
            owner_kind: kind, owner_id: id, before:, after:,
            preconditions:, dependencies: [] }
        end
      end

      def identity_claim_preconditions(kind, id, pool, path, exclude_id: nil)
        owner = { 'kind' => 'full_db_owner_absent',
                  'table' => 'storage_filesystem_identities',
                  'owner_kind' => kind, 'owner_id' => id.to_s }
        node_path = { 'kind' => 'full_db_node_path_absent',
                      'table' => 'storage_filesystem_identities',
                      'node_id' => pool.fetch('node_id').to_s, 'zfs_path' => path }
        digest = { 'kind' => 'full_db_node_path_digest_absent',
                   'table' => 'storage_filesystem_identities',
                   'node_id' => pool.fetch('node_id').to_s,
                   'path_digest' => Digest::SHA256.hexdigest(path.b) }
        if exclude_id
          owner['exclude_id'] = exclude_id.to_s
          node_path['exclude_id'] = exclude_id.to_s
          digest['exclude_id'] = exclude_id.to_s
        end
        [owner, node_path, digest]
      end

      def single_owner_fk?(identity, kind, id)
        claims = CATALOG_OWNERS.filter_map do |column, owner_kind|
          [owner_kind, identity[column].to_s] if identity[column]
        end
        claims == [[kind, id.to_s]]
      end

      def origin_proposal(finding)
        return unless two_pass_complete?

        evidence = finding.fetch('evidence')
        source_path = evidence.fetch('source')
        clone_path = evidence.fetch('clone')
        source = @zfs[source_path]
        clone = @zfs[clone_path]
        return unless source && clone && source['type'] == 'snapshot' &&
                      clone['type'] == 'filesystem' && clone['origin'] == source_path &&
                      source.fetch('clones', []).include?(clone_path)
        return unless source['guid'] && source['owner_guid'] && clone['guid'] &&
                      source['owner_path'] &&
                      source_path.start_with?("#{source['owner_path']}@") &&
                      @zfs.dig(source['owner_path'], 'type') == 'filesystem' &&
                      @zfs.dig(source['owner_path'], 'guid').to_s == source['owner_guid'].to_s
        return unless source['guid'].to_s == evidence['source_guid'].to_s &&
                      clone['guid'].to_s == evidence['clone_guid'].to_s

        owner = clone_owner(clone)
        return unless owner

        owner_kind, owner_id, identity_id, identity, owner_dependencies = owner

        sources = source_occurrences(source)
        return unless sources.length == 1

        source_kind, source_id, source_row, source_dependencies, source_claims = sources.first
        return if unsettled_effect?(clone_path, owner_kind, owner_id) ||
                  unsettled_effect?(source_path, source_kind, source_id)

        column = if source_kind == 'SnapshotInPool'
                   'origin_snapshot_in_pool_id'
                 else
                   'origin_snapshot_in_pool_in_branch_id'
                 end
        before = identity && { 'origin_state' => identity['origin_state'], column => nil }
        after = { 'origin_state' => '2', column => source_id }
        source_table = source_kind == 'SnapshotInPool' ? 'snapshot_in_pools' : 'snapshot_in_pool_in_branches'
        preconditions = [
          catalog_precondition(CATALOG_OWNERS_TABLE.fetch(owner_kind), owner_id,
                               row(CATALOG_OWNERS_TABLE.fetch(owner_kind), owner_id)),
          catalog_precondition(source_table, source_id, source_row),
          { 'kind' => 'physical_edge', 'digest' => @store.hmac({
                                                                 'source' => source, 'clone' => clone
                                                               }) }
        ].sort_by { |item| Format.canonical(item) }
        if identity
          preconditions << catalog_precondition('storage_filesystem_identities', identity_id,
                                                identity)
        end
        pool = row('pools', @manifest.dig('scope', 'pool_id'))
        preconditions.concat(identity_claim_preconditions(
                               owner_kind, owner_id, pool, clone_path, exclude_id: identity_id
                             ))
        preconditions.concat(source_claims)
        { operation: 'set_filesystem_origin',
          target_kind: identity ? 'StorageFilesystemIdentity' : owner_kind,
          target_id: identity_id || owner_id, owner_kind:, owner_id:,
          before:, after:, preconditions: preconditions.sort_by { |item| Format.canonical(item) },
          dependencies: (owner_dependencies + source_dependencies).uniq.sort }
      end

      def clone_owner(clone)
        pool = row('pools', @manifest.dig('scope', 'pool_id'))
        return unless pool

        claims = catalog_claims_at_path(clone.fetch('path'), pool)
        return unless claims.length == 1

        kind, id = claims.first
        rows = filesystem_identity_claims(kind, id, pool['node_id'], clone['path'])
        return if rows.length > 1
        return if conflicting_node_digest_claim?(pool['node_id'], clone['path'],
                                                 exclude_id: rows.first&.first)

        if rows.any?
          identity_id, identity = rows.first
          return if identity['origin_snapshot_in_pool_id'] ||
                    identity['origin_snapshot_in_pool_in_branch_id']
          return [kind, id, identity_id, identity, []] if exact_clone_owner?(identity, clone)
        end

        finding = legacy_finding(kind, id)
        proposal = finding && filesystem_proposal(finding)
        return unless proposal &&
                      %w[create_filesystem_identity backfill_filesystem_identity]
                      .include?(proposal.fetch(:operation))

        identity_id, identity = rows.first if rows.any?
        [kind, id, identity_id, identity, [action_for(finding).fetch('fields').fetch('action_key')]]
      end

      def exact_clone_owner?(identity, clone)
        pool = row('pools', identity['pool_id'])
        return false unless pool && pool['id'].to_s == @manifest.dig('scope', 'pool_id').to_s &&
                            pool['node_id'].to_s == @manifest.dig('scope', 'node_id').to_s &&
                            identity['node_id'].to_s == pool['node_id'].to_s &&
                            identity['physical_presence'].to_s == '1' &&
                            identity['zfs_guid'].to_s == clone['guid'].to_s &&
                            identity['zfs_path'] == clone['path'] &&
                            identity['path_digest'] == Digest::SHA256.hexdigest(clone.fetch('path').b) &&
                            %w[0 1].include?(identity['origin_state'].to_s)

        claims = CATALOG_OWNERS.filter_map do |column, kind|
          [kind, identity[column]] if identity[column]
        end
        return false unless claims.length == 1

        kind, id = claims.first
        return false unless single_owner_fk?(identity, kind, id)

        catalog_owner_path(kind, id, pool) == clone['path'] &&
          unique_catalog_path_claim?(kind, id, clone['path'], pool)
      end

      def unique_catalog_path_claim?(kind, id, path, pool)
        return false if overlapping_other_pool?(path, pool)

        catalog_claims_at_path(path, pool) == [[kind, id.to_s]]
      end

      def overlapping_other_pool?(path, pool)
        @db['pools'].any? do |other_id, other|
          next false if other_id == pool['id'].to_s ||
                        other['node_id'].to_s != pool['node_id'].to_s

          other_root = other['filesystem']
          path == other_root || path.start_with?("#{other_root}/", "#{other_root}@")
        end
      end

      def catalog_claims_at_path(path, pool)
        @catalog_claims ||= {}
        @catalog_claims[pool['id'].to_s] ||= begin
          claims = Hash.new { |hash, key| hash[key] = [] }
          CATALOG_OWNERS_TABLE.each do |owner_kind, table|
            @db[table].each_key do |owner_id|
              owner_path = catalog_owner_path(owner_kind, owner_id, pool)
              claims[owner_path] << [owner_kind, owner_id] if owner_path
            end
          end
          claims
        end
        @catalog_claims[pool['id'].to_s][path]
      end

      def catalog_owner_path(kind, id, pool)
        root = pool.fetch('filesystem')
        case kind
        when 'Pool'
          root if id.to_s == pool.fetch('id').to_s
        when 'DatasetInPool'
          dip = row('dataset_in_pools', id)
          dataset = dip && row('datasets', dip['dataset_id'])
          "#{root}/#{dataset.fetch('full_name')}" if dip && dataset &&
                                                     dip['pool_id'].to_s == pool['id'].to_s
        when 'DatasetTree', 'Branch'
          branch = kind == 'Branch' ? row('branches', id) : nil
          return if kind == 'Branch' && !branch

          tree_id = branch ? branch['dataset_tree_id'] : id
          tree = row('dataset_trees', tree_id)
          return unless tree

          base = catalog_owner_path('DatasetInPool', tree['dataset_in_pool_id'], pool)
          return unless base

          path = "#{base}/tree.#{tree.fetch('index')}"
          branch ? "#{path}/branch-#{branch.fetch('name')}.#{branch.fetch('index')}" : path
        when 'SnapshotInPoolClone'
          owner = row('snapshot_in_pool_clones', id)
          sip = owner && row('snapshot_in_pools', owner['snapshot_in_pool_id'])
          dip = sip && row('dataset_in_pools', sip['dataset_in_pool_id'])
          "#{root}/vpsadmin/mount/#{owner.fetch('name')}" if dip &&
                                                             dip['pool_id'].to_s == pool['id'].to_s
        end
      end

      def source_occurrences(source)
        index_snapshot_occurrences!
        key = [@manifest.dig('scope', 'pool_id').to_s, source['path']]
        @source_rows_by_pool_path[key].filter_map do |kind, id, occurrence|
          source_occurrence(kind, id, occurrence, source)
        end
      end

      def source_occurrence(kind, id, occurrence, source)
        path, pool = snapshot_catalog_path(kind, id, occurrence)
        return unless path == source['path'] && pool &&
                      pool['id'].to_s == @manifest.dig('scope', 'pool_id').to_s &&
                      unique_snapshot_claim?(kind, id, path, pool)

        owner_evidence = source_owner_dependencies(kind, occurrence, source, pool)
        return unless owner_evidence

        owner_dependencies, owner_claims = owner_evidence

        if exact_source?(occurrence, source)
          [kind, id, occurrence, owner_dependencies, owner_claims]
        else
          finding = legacy_finding(kind, id)
          proposal = finding && snapshot_proposal(finding)
          return unless proposal && proposal.fetch(:after)['zfs_guid'].to_s == source['guid'].to_s

          dependency = action_for(finding).fetch('fields').fetch('action_key')
          [kind, id, occurrence, (owner_dependencies + [dependency]).uniq.sort, owner_claims]
        end
      end

      def source_owner_dependencies(kind, occurrence, source, pool)
        if kind == 'SnapshotInPool'
          owner_kind = 'DatasetInPool'
          owner_id = occurrence.fetch('dataset_in_pool_id')
        else
          owner_kind = 'Branch'
          owner_id = occurrence.fetch('branch_id')
        end
        path = catalog_owner_path(owner_kind, owner_id, pool)
        return unless path == source['owner_path']

        owner = @zfs[path]
        return unless owner && owner['type'] == 'filesystem' &&
                      owner['guid'].to_s == source['owner_guid'].to_s

        identities = filesystem_identity_claims(owner_kind, owner_id, pool['node_id'], path)
        return if identities.length > 1
        return if conflicting_node_digest_claim?(pool['node_id'], path,
                                                 exclude_id: identities.first&.first)

        identity_id = identities.first&.first
        claim_preconditions = identity_claim_preconditions(
          owner_kind, owner_id, pool, path, exclude_id: identity_id
        )
        if identities.any?
          _id, identity = identities.first
          claim_preconditions << catalog_precondition('storage_filesystem_identities', identity_id,
                                                      identity)
          return [[], claim_preconditions] if single_owner_fk?(identity, owner_kind, owner_id) &&
                                              identity['pool_id'].to_s == pool['id'].to_s &&
                                              identity['node_id'].to_s == pool['node_id'].to_s &&
                                              identity['zfs_path'] == path &&
                                              identity['path_digest'] == Digest::SHA256.hexdigest(path.b) &&
                                              identity['zfs_guid'].to_s == owner['guid'].to_s &&
                                              identity['physical_presence'].to_s == '1'
        end

        finding = legacy_finding(owner_kind, owner_id)
        proposal = finding && filesystem_proposal(finding)
        return unless proposal &&
                      %w[create_filesystem_identity backfill_filesystem_identity]
                      .include?(proposal.fetch(:operation))

        [[action_for(finding).fetch('fields').fetch('action_key')], claim_preconditions]
      end

      def exact_source?(occurrence, source)
        occurrence['zfs_path'] == source['path'] &&
          occurrence['zfs_guid'].to_s == source['guid'].to_s &&
          occurrence['zfs_owner_fs_guid'].to_s == source['owner_guid'].to_s &&
          occurrence['physical_presence'].to_s == '1'
      end

      def catalog_precondition(table, id, value)
        { 'kind' => 'catalog_row', 'table' => table, 'id' => id,
          'digest' => @store.hmac(value) }
      end
    end
  end
end
