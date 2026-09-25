module VpsAdmin
  module StorageReconciler
    # Offline, advisory matcher. It never infers a repair from absent history.
    class Comparator
      class Invalid < StandardError; end

      MAX_FINDINGS = 200_000
      POOL_STRUCTURAL_DATASETS = %w[
        vpsadmin vpsadmin/config vpsadmin/download vpsadmin/mount
      ].freeze
      PENDING_NAME_SUFFIX = ' (unconfirmed)'.freeze

      attr_reader :findings

      def initialize(db_records:, zfs_records:, manifest:, store:)
        @db_records = db_records
        @zfs_records = zfs_records
        @manifest = manifest
        @store = store
        @findings = []
        @scope = manifest.fetch('scope')
        @mode = manifest.fetch('mode')
        raise Invalid, 'unsupported capture mode' unless %w[bootstrap steady].include?(@mode)

        @db = Hash.new { |hash, key| hash[key] = {} }
        @zfs = {}
        index_records!
      end

      def compare
        pool = row('pools', @scope.fetch('pool_id'))
        raise Invalid, 'selected Pool is absent' unless pool
        raise Invalid, 'managed root differs from DB' unless
          pool['filesystem'] == @scope.fetch('managed_root')

        expected = expected_paths(pool)
        check_disk_objects(expected)
        check_catalog_identities(expected)
        check_clone_edges
        check_reference_counts
        check_parent_links
        check_pending_datasets
        check_head_flags(pool)
        findings.sort_by! do |finding|
          fields = finding.fetch('fields')
          [fields.fetch('code'), fields.fetch('finding_key')]
        end
      end

      private

      def index_records!
        @db_records.each do |record|
          Format.verify_record!(record, expected_kind: 'db_object')
          data = record.fetch('fields')
          table = data.fetch('table')
          id = data.fetch('id').to_s
          raise Invalid, 'duplicate DB row' if @db[table].has_key?(id)

          @db[table][id] = data.fetch('fields')
        end
        @zfs_records.each do |record|
          Format.verify_record!(record, expected_kind: 'zfs_object')
          fields = record.fetch('fields')
          path = fields.fetch('path')
          raise Invalid, 'duplicate ZFS path' if @zfs.has_key?(path)

          @zfs[path] = fields
        end
      end

      def row(table, id)
        @db[table][id.to_s]
      end

      def selected_dips
        @db['dataset_in_pools'].select do |_id, dip|
          dip['pool_id'].to_s == @scope.fetch('pool_id').to_s
        end
      end

      def expected_paths(pool)
        expected = { pool.fetch('filesystem') => [['Pool', @scope.fetch('pool_id').to_s]] }
        dips = selected_dips
        dips.each do |id, dip|
          dataset = row('datasets', dip['dataset_id'])
          next unless dataset

          expected["#{pool.fetch('filesystem')}/#{dataset.fetch('full_name')}"] ||= []
          expected["#{pool.fetch('filesystem')}/#{dataset.fetch('full_name')}"] << ['DatasetInPool', id]
        end
        @db['dataset_trees'].each do |id, tree|
          base = dip_path(tree['dataset_in_pool_id'], pool)
          next unless base

          expected["#{base}/tree.#{tree.fetch('index')}"] ||= []
          expected["#{base}/tree.#{tree.fetch('index')}"] << ['DatasetTree', id]
        end
        @db['branches'].each do |id, branch|
          path = branch_path(branch, pool)
          next unless path

          expected[path] ||= []
          expected[path] << ['Branch', id]
          next if @zfs.has_key?(path)

          finding('db_only_branch', 'Branch', id,
                  { 'expected_path' => path, 'confirmed' => branch['confirmed'] },
                  %w[historical_destroy_confirmation_not_captured fresh_frozen_absence_required])
        end
        @db['snapshot_in_pools'].each do |id, sip|
          dip = row('dataset_in_pools', sip['dataset_in_pool_id'])
          next unless dip && dip['pool_id'].to_s == @scope.fetch('pool_id').to_s

          snapshot = row('snapshots', sip['snapshot_id'])
          next unless snapshot

          if pool['role'].to_s == '2'
            @db['snapshot_in_pool_in_branches'].each do |sipb_id, sipb|
              next unless sipb['snapshot_in_pool_id'].to_s == id

              branch = row('branches', sipb['branch_id'])
              base = branch && branch_path(branch, pool)
              next unless base

              path = "#{base}@#{snapshot.fetch('name')}"
              (expected[path] ||= []) << ['SnapshotInPoolInBranch', sipb_id]
            end
          else
            base = dip_path(sip['dataset_in_pool_id'], pool)
            (expected["#{base}@#{snapshot.fetch('name')}"] ||= []) << ['SnapshotInPool', id] if base
          end
        end
        @db['snapshot_in_pool_clones'].each do |id, clone|
          sip = row('snapshot_in_pools', clone['snapshot_in_pool_id'])
          dip = sip && row('dataset_in_pools', sip['dataset_in_pool_id'])
          next unless dip && dip['pool_id'].to_s == @scope.fetch('pool_id').to_s

          path = "#{pool.fetch('filesystem')}/vpsadmin/mount/#{clone.fetch('name')}"
          (expected[path] ||= []) << ['SnapshotInPoolClone', id]
        end
        expected
      end

      def dip_path(dip_id, pool)
        dip = row('dataset_in_pools', dip_id)
        return unless dip && dip['pool_id'].to_s == @scope.fetch('pool_id').to_s

        dataset = row('datasets', dip['dataset_id'])
        "#{pool.fetch('filesystem')}/#{dataset.fetch('full_name')}" if dataset
      end

      def branch_path(branch, pool)
        tree = row('dataset_trees', branch['dataset_tree_id'])
        return unless tree

        base = dip_path(tree['dataset_in_pool_id'], pool)
        "#{base}/tree.#{tree.fetch('index')}/branch-#{branch.fetch('name')}.#{branch.fetch('index')}" if base
      end

      def check_disk_objects(expected)
        root = @scope.fetch('managed_root')
        structural_paths = POOL_STRUCTURAL_DATASETS.to_set { |suffix| "#{root}/#{suffix}" }
        pending_candidates = pending_snapshot_candidates(expected)
        candidate_physical_paths = pending_candidates.values.to_set { |pair| pair.fetch(:physical_path) }
        pending_candidates.each do |catalog_path, pair|
          pair.fetch(:owners).each do |owner|
            pending_snapshot_finding(catalog_path, pair, owner)
          end
        end
        expected.each do |path, owners|
          next if @zfs.has_key?(path)
          next if owners.any? { |kind, _id| kind == 'Branch' }
          next if pending_candidates.has_key?(path)

          finding('db_object_missing_on_zfs', owners.first[0], owners.first[1],
                  { 'expected_path' => path }, %w[fresh_frozen_absence_required])
        end
        @zfs.each do |path, fields|
          next unless path == root || path.start_with?("#{root}/", "#{root}@")
          next if expected.has_key?(path)
          next if candidate_physical_paths.include?(path)
          next if structural_paths.include?(path) && fields['type'] == 'filesystem'

          opaque = @store.opaque_disk_key(
            node_id: @scope.fetch('node_id'), zpool: @scope.fetch('zpool'),
            path:, type: fields.fetch('type'), guid: fields.fetch('guid')
          )
          finding('disk_only_object', 'ZFS', opaque, fields,
                  %w[no_catalog_owner_proof no_disk_mutation_action], counterpart: opaque)
        end
      end

      def pending_snapshot_finding(catalog_path, pair, owner)
        bound = owner.fetch(:target_ids).any?
        blockers = %w[pending_snapshot_confirmation physical_identity_not_proved]
        blockers << 'unique_catalog_owner_not_proved' if pair.fetch(:owners).size != 1
        if bound
          blockers << 'signed_command_not_captured'
          blockers << 'settled_receipt_not_matching' unless owner.fetch(:receipt_matches)
          blockers << 'unsettled_mutation_intent' if owner.fetch(:unsettled)
          blockers << 'unique_intent_not_proved' if owner.fetch(:target_ids).size != 1
          blockers << 'owner_guid_conflicts_with_target' if owner.fetch(:owner_conflict)
          if (owner.fetch(:raw_target_ids) - owner.fetch(:target_ids)).any?
            blockers << 'conflicting_intent_target_captured'
          end
        elsif owner.fetch(:raw_target_ids).empty?
          blockers << 'exact_intent_target_not_captured'
          blockers.push('no_catalog_owner_proof', 'no_disk_mutation_action')
        else
          blockers << 'intent_target_binding_conflict'
          blockers.push('no_catalog_owner_proof', 'no_disk_mutation_action')
        end

        physical = pair.fetch(:physical)
        opaque = @store.opaque_disk_key(
          node_id: @scope.fetch('node_id'), zpool: @scope.fetch('zpool'),
          path: pair.fetch(:physical_path), type: physical.fetch('type'), guid: physical.fetch('guid')
        )
        kind = bound ? owner.fetch(:kind) : 'ZFS'
        id = bound ? owner.fetch(:id) : opaque
        finding(bound ? 'pending_snapshot_path_unresolved' : 'pending_snapshot_possible_pair_unresolved',
                kind, id,
                { 'catalog_path' => catalog_path, 'catalog_kind' => owner.fetch(:kind),
                  'catalog_id' => owner.fetch(:id),
                  'physical_path' => pair.fetch(:physical_path),
                  'physical_guid' => physical.fetch('guid'),
                  'physical_owner_guid' => physical.fetch('owner_guid'),
                  'candidate_owner_count' => pair.fetch(:owners).size,
                  'captured_target_ids' => owner.fetch(:target_ids),
                  'other_target_ids' => owner.fetch(:raw_target_ids) - owner.fetch(:target_ids),
                  'receipt_matches' => owner.fetch(:receipt_matches) },
                blockers, counterpart: bound ? nil : "#{owner.fetch(:kind)}:#{owner.fetch(:id)}")
      end

      def pending_snapshot_candidates(expected)
        targets_by_sip = @db['storage_mutation_targets'].group_by do |_id, target|
          target['snapshot_in_pool_id'].to_s
        end
        expected.each_with_object({}) do |(catalog_path, owners), ret|
          next unless catalog_path.end_with?(PENDING_NAME_SUFFIX)

          physical_path = catalog_path.delete_suffix(PENDING_NAME_SUFFIX)
          physical = @zfs[physical_path]
          next unless physical && physical['type'] == 'snapshot' &&
                      physical['owner_path'] == physical_path.split('@', 2).first
          next if expected.has_key?(physical_path)

          pending_owners = owners.map do |kind, id|
            sip_id = pending_snapshot_sip_id(kind, id)
            next unless sip_id

            raw_targets = targets_by_sip.fetch(sip_id, [])
            targets = raw_targets.filter_map do |target_id, target|
              pending_snapshot_target(target_id, target, sip_id, physical_path, physical)
            end

            { kind:, id:, target_ids: targets.map { |target| target.fetch(:id) }.sort,
              raw_target_ids: raw_targets.map(&:first).sort,
              receipt_matches: targets.any? { |target| target.fetch(:receipt_matches) },
              unsettled: targets.any? { |target| target.fetch(:unsettled) },
              owner_conflict: targets.any? { |target| target.fetch(:owner_conflict) } }
          end
          next if pending_owners.any?(&:nil?)

          ret[catalog_path] = { physical_path:, physical:, owners: pending_owners }
        end
      end

      def pending_snapshot_sip_id(kind, id)
        sip_id = if kind == 'SnapshotInPool'
                   id
                 elsif kind == 'SnapshotInPoolInBranch'
                   row('snapshot_in_pool_in_branches', id)&.fetch('snapshot_in_pool_id')
                 end
        sip = row('snapshot_in_pools', sip_id)
        snapshot = sip && row('snapshots', sip['snapshot_id'])
        return unless snapshot && snapshot['confirmed'].to_s == '0' &&
                      snapshot['name'].to_s.end_with?(PENDING_NAME_SUFFIX)

        sip_id.to_s
      end

      def pending_snapshot_target(id, target, sip_id, physical_path, physical)
        return unless target['kind'] == 'snapshot_create' && target['command_key'].to_s == '5204' &&
                      target['expected_path'] == physical_path &&
                      target['catalog_kind'] == 'SnapshotInPool' &&
                      target['catalog_id'].to_s == sip_id

        sip = row('snapshot_in_pools', sip_id)
        dip = row('dataset_in_pools', sip['dataset_in_pool_id'])
        intent = row('storage_mutation_intents', target['storage_mutation_intent_id'])
        intent_scope = row('storage_mutation_intent_scopes', target['storage_mutation_intent_scope_id'])
        scope = intent_scope && row('storage_integrity_scopes', intent_scope['storage_integrity_scope_id'])
        transaction = intent && row('transactions', intent['transaction_id'])
        chain = intent && row('transaction_chains', intent['transaction_chain_id'])
        return unless dip && intent && intent_scope && scope && transaction && chain

        pool = row('pools', @scope.fetch('pool_id'))
        return unless dip['pool_id'].to_s == @scope.fetch('pool_id').to_s &&
                      pool && pool['node_id'].to_s == @scope.fetch('node_id').to_s &&
                      intent['kind'] == 'snapshot_create' &&
                      intent['node_catalog_id'].to_s == @scope.fetch('node_id').to_s &&
                      intent['transaction_chain_id'].to_s == transaction['transaction_chain_id'].to_s &&
                      transaction['handle'].to_s == '5204' &&
                      transaction['node_id'].to_s == @scope.fetch('node_id').to_s &&
                      scope['scope_key'] == "dip:#{dip.fetch('id')}" &&
                      scope['pool_catalog_id'].to_s == @scope.fetch('pool_id').to_s &&
                      scope['dataset_in_pool_catalog_id'].to_s == dip.fetch('id').to_s &&
                      scope['dataset_in_pool_id'].to_s == dip.fetch('id').to_s &&
                      intent_scope['storage_mutation_intent_id'].to_s == intent.fetch('id').to_s &&
                      intent['protocol_version'].to_s == '1' &&
                      intent['token'].to_s.match?(/\A[0-9a-f]{64}\z/) &&
                      intent['manifest_digest'].to_s.match?(/\A[0-9a-f]{64}\z/)

        @attempts_by_intent ||= @db['storage_mutation_attempts'].group_by do |_attempt_id, attempt|
          attempt['storage_mutation_intent_id'].to_s
        end
        @observations_by_target ||= @db['storage_mutation_target_observations'].group_by do |_id, observation|
          observation['storage_mutation_target_id'].to_s
        end
        attempts = @attempts_by_intent.fetch(intent.fetch('id').to_s, []).select do |_id, attempt|
          attempt['command_key'].to_s == '5204'
        end
        receipt_matches = attempts.any? do |attempt_id, attempt|
          next false unless attempt['direction'].to_s == '0' &&
                            attempt['state'].to_s == '1' && attempt['finished_at']

          @observations_by_target.fetch(id.to_s, []).any? do |_observation_id, observation|
            observation['storage_mutation_attempt_id'].to_s == attempt_id &&
              observation['after_presence'].to_s == '1' &&
              observation['before_presence'].to_s == '2' &&
              observation['after_path_digest'] == Digest::SHA256.hexdigest(physical_path) &&
              observation['after_guid'].to_s == physical['guid'].to_s &&
              observation['after_owner_fs_guid'].to_s == physical['owner_guid'].to_s &&
              observation['before_owner_fs_guid'].to_s == physical['owner_guid'].to_s
          end
        end
        owner_conflict = target['expected_owner_fs_guid'] &&
                         target['expected_owner_fs_guid'].to_s != physical['owner_guid'].to_s
        unsettled = %w[0 1 5].include?(intent['phase'].to_s) || attempts.any? do |_attempt_id, attempt|
          %w[0 3].include?(attempt['state'].to_s)
        end
        { id:, receipt_matches: receipt_matches && !owner_conflict,
          unsettled:, owner_conflict: }
      end

      def check_catalog_identities(expected)
        owner_column = {
          'Pool' => 'owner_pool_id',
          'DatasetInPool' => 'dataset_in_pool_id',
          'DatasetTree' => 'dataset_tree_id',
          'Branch' => 'branch_id',
          'SnapshotInPoolClone' => 'snapshot_in_pool_clone_id'
        }
        expected.each do |path, owners|
          object = @zfs[path]
          next unless object

          if owners.size != 1
            finding('catalog_path_owner_ambiguous', 'ZFS', nil,
                    { 'path' => path, 'owners' => owners },
                    %w[unique_catalog_owner_required], counterpart: @store.opaque_disk_key(
                      node_id: @scope.fetch('node_id'), zpool: @scope.fetch('zpool'),
                      path:, type: object.fetch('type'), guid: object.fetch('guid')
                    ))
            next
          end
          kind, id = owners.first
          expected_type = if kind.start_with?('SnapshotInPool') && kind != 'SnapshotInPoolClone'
                            'snapshot'
                          else
                            'filesystem'
                          end
          if object['type'] != expected_type
            finding('catalog_type_mismatch', kind, id,
                    { 'path' => path, 'expected' => expected_type, 'observed' => object['type'] },
                    %w[exact_physical_identity_required])
            next
          end

          identity = if expected_type == 'snapshot'
                       row(kind == 'SnapshotInPool' ? 'snapshot_in_pools' : 'snapshot_in_pool_in_branches', id)
                     else
                       column = owner_column.fetch(kind)
                       @db['storage_filesystem_identities'].values.find do |item|
                         item[column].to_s == id.to_s
                       end
                     end
          if identity.nil?
            finding('legacy_identity_unverified', kind, id, { 'path' => path },
                    %w[catalog_physical_identity_unpublished])
            next
          end
          catalog_path = identity['zfs_path']
          if catalog_path && catalog_path != path
            finding('catalog_path_mismatch', kind, id,
                    { 'expected' => path, 'catalog' => catalog_path },
                    %w[exact_physical_identity_required])
          end
          catalog_guid = identity['zfs_guid']
          if catalog_guid && catalog_guid.to_s != object['guid'].to_s
            finding('catalog_guid_mismatch', kind, id,
                    { 'path' => path, 'catalog' => catalog_guid, 'observed' => object['guid'] },
                    %w[same_path_replacement_possible])
          end
          if expected_type == 'snapshot'
            owner_guid = identity['zfs_owner_fs_guid']
            if owner_guid && owner_guid.to_s != object['owner_guid'].to_s
              finding('catalog_owner_guid_mismatch', kind, id,
                      { 'path' => path, 'catalog' => owner_guid,
                        'observed' => object['owner_guid'] },
                      %w[owner_filesystem_replacement_possible])
            end
          end
          if identity['physical_presence'].to_s == '2'
            finding('catalog_presence_mismatch', kind, id,
                    { 'path' => path, 'catalog_presence' => 'missing' },
                    %w[physical_presence_conflicts_with_catalog])
          elsif identity['physical_presence'].to_s != '1' || !catalog_path || !catalog_guid ||
                (expected_type == 'snapshot' && !identity['zfs_owner_fs_guid'])
            finding('legacy_identity_unverified', kind, id, { 'path' => path },
                    %w[catalog_physical_identity_unpublished])
          end
        end
      end

      def check_clone_edges
        seen = Set.new
        @zfs.each do |path, fields|
          source = fields['origin']
          next unless source && @zfs[source]
          next unless within_selected_root?(source) || within_selected_root?(path)

          unless @zfs[source].fetch('clones', []).include?(path)
            finding('zfs_clone_edge_mismatch', 'ZFS edge', nil,
                    { 'source' => source, 'clone' => path },
                    %w[reciprocal_physical_edge_required], counterpart: edge_key(source, path))
            next
          end

          edge = [source, path]
          next if seen.include?(edge)

          seen << edge
          identities = @db['storage_filesystem_identities'].values.select do |identity|
            identity['zfs_path'] == path
          end
          if identities.length > 1
            finding('clone_origin_owner_ambiguous', 'ZFS edge', nil,
                    { 'source' => source, 'clone' => path, 'claim_count' => identities.length },
                    %w[unique_catalog_owner_required], counterpart: edge_key(*edge))
            next
          end
          identity = identities.first
          linked_sip = identity && identity['origin_snapshot_in_pool_id']
          linked_sipb = identity && identity['origin_snapshot_in_pool_in_branch_id']
          if !identity || (!linked_sip && !linked_sipb)
            finding('reciprocal_clone_origin_unrepresented', 'ZFS edge', nil,
                    { 'source' => source, 'clone' => path,
                      'source_guid' => @zfs[source]['guid'], 'clone_guid' => fields['guid'] },
                    %w[unique_catalog_source_unproved historical_promotion_proof_not_captured],
                    counterpart: edge_key(*edge))
            next
          end
          source_signature = if linked_sip && !linked_sipb
                               sip_signature(linked_sip)
                             elsif linked_sipb && !linked_sip
                               sipb_signature(linked_sipb)
                             end
          if !source_signature || source_signature.fetch('path') != source ||
             @zfs[source]['type'] != 'snapshot' ||
             (identity['zfs_guid'] && identity['zfs_guid'].to_s != fields['guid'].to_s) ||
             (source_signature['guid'] && source_signature['guid'].to_s != @zfs[source]['guid'].to_s) ||
             (source_signature['owner_guid'] &&
               source_signature['owner_guid'].to_s != @zfs[source]['owner_guid'].to_s)
            finding('clone_origin_link_mismatch', 'ZFS edge', nil,
                    { 'source' => source, 'clone' => path,
                      'source_catalog' => source_signature, 'clone_catalog_guid' => identity['zfs_guid'] },
                    %w[stale_or_wrong_origin_link], counterpart: edge_key(*edge))
            next
          end
          next if identity['origin_state'].to_s == '2' &&
                  identity['physical_presence'].to_s == '1' &&
                  identity['zfs_guid'] && source_signature['guid'] &&
                  source_signature['owner_guid'] && source_signature['presence'].to_s == '1'

          finding('clone_origin_link_unverified', 'ZFS edge', nil,
                  { 'source' => source, 'clone' => path },
                  %w[physical_identity_or_origin_state_unpublished],
                  counterpart: edge_key(*edge))
        end
      end

      def sip_signature(id)
        sip = row('snapshot_in_pools', id)
        return unless sip

        dip = row('dataset_in_pools', sip['dataset_in_pool_id'])
        pool = dip && row('pools', dip['pool_id'])
        return unless pool && pool['role'].to_s != '2'

        snapshot = row('snapshots', sip['snapshot_id'])
        base = any_dip_path(sip['dataset_in_pool_id'], pool)
        return unless snapshot && base

        { 'path' => "#{base}@#{snapshot.fetch('name')}",
          'guid' => sip['zfs_guid'], 'owner_guid' => sip['zfs_owner_fs_guid'],
          'presence' => sip['physical_presence'] }
      end

      def sipb_signature(id)
        sipb = row('snapshot_in_pool_in_branches', id)
        sip = sipb && row('snapshot_in_pools', sipb['snapshot_in_pool_id'])
        branch = sipb && row('branches', sipb['branch_id'])
        dip = sip && row('dataset_in_pools', sip['dataset_in_pool_id'])
        pool = dip && row('pools', dip['pool_id'])
        snapshot = sip && row('snapshots', sip['snapshot_id'])
        return unless pool && pool['role'].to_s == '2' && branch && snapshot

        tree = row('dataset_trees', branch['dataset_tree_id'])
        return unless tree && tree['dataset_in_pool_id'].to_s == sip['dataset_in_pool_id'].to_s

        base = any_branch_path(branch, pool)
        return unless base

        { 'path' => "#{base}@#{snapshot.fetch('name')}",
          'guid' => sipb['zfs_guid'], 'owner_guid' => sipb['zfs_owner_fs_guid'],
          'presence' => sipb['physical_presence'] }
      end

      def any_dip_path(dip_id, pool)
        dip = row('dataset_in_pools', dip_id)
        return unless dip && dip['pool_id'].to_s == pool['id'].to_s

        dataset = row('datasets', dip['dataset_id'])
        "#{pool.fetch('filesystem')}/#{dataset.fetch('full_name')}" if dataset
      end

      def any_branch_path(branch, pool)
        tree = row('dataset_trees', branch['dataset_tree_id'])
        return unless tree

        base = any_dip_path(tree['dataset_in_pool_id'], pool)
        "#{base}/tree.#{tree.fetch('index')}/branch-#{branch.fetch('name')}.#{branch.fetch('index')}" if base
      end

      def check_reference_counts
        return unless @manifest.fetch('db')['reference_closure'] ==
                      'selected_pool_sips_recursive_sipb_and_clones'

        selected_sips = @db['snapshot_in_pools'].select do |_id, sip|
          selected_dips.has_key?(sip['dataset_in_pool_id'].to_s)
        end
        incoming = Hash.new(0)
        pending = Hash.new(0)
        @db['snapshot_in_pool_in_branches'].each_value do |sipb|
          parent = row('snapshot_in_pool_in_branches', sipb['snapshot_in_pool_in_branch_id'])
          next unless parent

          target = sipb['confirmed'].to_s == '1' && parent['confirmed'].to_s == '1' ? incoming : pending
          target[parent['snapshot_in_pool_id'].to_s] += 1
        end
        @db['snapshot_in_pool_clones'].each_value do |clone|
          target = clone['confirmed'].to_s == '1' ? incoming : pending
          target[clone['snapshot_in_pool_id'].to_s] += 1
        end
        selected_sips.each do |id, sip|
          stored = Integer(sip.fetch('reference_count'))
          minimum = incoming[id]
          next if stored == minimum && pending[id] == 0

          code = if stored < minimum
                   'reference_count_below_confirmed_minimum'
                 elsif stored > minimum
                   'reference_count_surplus_unresolved'
                 else
                   'reference_count_pending_references'
                 end
          finding(code, 'SnapshotInPool', id,
                  { 'stored' => stored, 'confirmed_minimum' => minimum,
                    'pending_references' => pending[id] },
                  %w[historical_confirmation_not_fully_captured count_semantics_require_proof])
        end
      end

      def check_parent_links
        selected_sip_ids = @db['snapshot_in_pools'].filter_map do |id, sip|
          id if selected_dips.has_key?(sip['dataset_in_pool_id'].to_s)
        end.to_set
        @db['snapshot_in_pool_in_branches'].each do |id, sipb|
          next unless selected_sip_ids.include?(sipb['snapshot_in_pool_id'].to_s)

          parent_id = sipb['snapshot_in_pool_in_branch_id']
          next unless parent_id
          next if row('snapshot_in_pool_in_branches', parent_id)

          finding('sipb_parent_unresolved', 'SnapshotInPoolInBranch', id,
                  { 'parent_id' => parent_id },
                  %w[full_database_parent_lookup_required no_fk_repair_proof])
        end
      end

      def check_pending_datasets
        selected_dataset_ids = selected_dips.values.to_set { |dip| dip['dataset_id'].to_s }
        @db['datasets'].each do |id, dataset|
          next unless selected_dataset_ids.include?(id)
          next unless dataset['confirmed'].to_s == '0'

          finding('pending_dataset_create', 'Dataset', id,
                  { 'confirmed' => dataset['confirmed'] },
                  %w[historical_create_confirmation_not_captured all_pool_physical_proof_required])
        end
      end

      def check_head_flags(pool)
        return unless pool['role'].to_s == '2'

        selected_dips.each_key do |id|
          trees = @db['dataset_trees'].select { |_tree_id, tree| tree['dataset_in_pool_id'].to_s == id }
          heads = trees.select { |_tree_id, tree| tree['head'].to_s == '1' }
          if heads.empty?
            finding('headless_backup_dip', 'DatasetInPool', id,
                    { 'tree_count' => trees.size },
                    %w[may_be_detached detachment_history_not_fully_captured])
          elsif heads.size > 1
            finding('multiple_head_trees', 'DatasetInPool', id,
                    { 'head_count' => heads.size }, %w[head_lineage_requires_proof])
          end
          heads.each_key do |tree_id|
            branch_count = @db['branches'].count do |_branch_id, branch|
              branch['dataset_tree_id'].to_s == tree_id && branch['head'].to_s == '1'
            end
            next if branch_count == 1

            finding('head_tree_branch_count', 'DatasetTree', tree_id,
                    { 'head_count' => branch_count }, %w[branch_lineage_requires_proof])
          end
        end
      end

      def finding(code, kind, id, evidence, blockers, counterpart: nil)
        raise Invalid, 'finding limit exceeded' if @findings.size >= MAX_FINDINGS

        identity = [Format::POLICY_VERSION, code, @scope.fetch('node_id').to_s,
                    @scope.fetch('pool_id').to_s, kind, id&.to_s, counterpart]
        key = Format.digest(identity)
        @findings << Format.record('finding', {
          'code' => code, 'finding_key' => key, 'subject_kind' => kind,
          'subject_id' => id&.to_s, 'scope' => @scope,
          'confidence' => 'advisory_unguarded', 'blockers' => blockers,
          'evidence' => evidence,
          'evidence_digest' => @store.hmac([
                                             evidence, @manifest.fetch('db').fetch('digest'),
                                             @manifest.fetch('zfs').fetch('digest'), @scope.fetch('mutation_epoch')
                                           ])
        })
      end

      def edge_key(source, clone)
        source_row = @zfs.fetch(source)
        clone_row = @zfs.fetch(clone)
        @store.opaque_edge_key(
          node_id: @scope.fetch('node_id'), zpool: @scope.fetch('zpool'),
          source:, source_type: source_row.fetch('type'), source_guid: source_row.fetch('guid'),
          clone:, clone_type: clone_row.fetch('type'), clone_guid: clone_row.fetch('guid')
        )
      end

      def within_selected_root?(path)
        root = @scope.fetch('managed_root')
        path == root || path.start_with?("#{root}/", "#{root}@")
      end
    end
  end
end
