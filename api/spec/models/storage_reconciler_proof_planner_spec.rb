# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler::ProofPlanner do
  let(:format) { VpsAdmin::StorageReconciler::Format }
  let(:root_path) { 'tank/backup' }
  let(:branch_path) { "#{root_path}/101/tree.0/branch-head.0" }
  let(:clone_path) { "#{root_path}/101/tree.0/branch-clone.2" }
  let(:source_path) { "#{branch_path}@snap" }

  def db(table, id, **fields)
    format.record('db_object', {
      'table' => table, 'id' => id.to_s,
      'fields' => { id: id, **fields }.transform_keys(&:to_s)
                                      .transform_values { |value| value&.to_s }
    })
  end

  def zfs(path, type, guid, **fields)
    format.record('zfs_object', {
      'path' => path, 'type' => type, 'guid' => guid.to_s,
      'owner_path' => nil, 'owner_guid' => nil, 'origin' => nil,
      'clones' => [], 'userrefs' => '0', 'deferred_destroy' => 'off',
      'creation' => '1', 'createtxg' => '1'
    }.merge(fields.transform_keys(&:to_s)))
  end

  def db_rows
    [
      db('pools', 1, node_id: 2, filesystem: root_path, role: 2),
      db('datasets', 10, full_name: '101', confirmed: 0),
      db('dataset_in_pools', 11, pool_id: 1, dataset_id: 10),
      db('dataset_trees', 20, dataset_in_pool_id: 11, index: 0, head: 0),
      db('branches', 30, dataset_tree_id: 20, name: 'head', index: 0, head: 0),
      db('branches', 31, dataset_tree_id: 20, name: 'empty', index: 1, head: 0),
      db('branches', 32, dataset_tree_id: 20, name: 'clone', index: 2, head: 0),
      db('snapshots', 40, dataset_id: 10, name: 'snap', confirmed: 1),
      db('snapshot_in_pools', 50, dataset_in_pool_id: 11,
                                  snapshot_id: 40, reference_count: 2),
      db('snapshot_in_pool_in_branches', 60, snapshot_in_pool_id: 50,
                                             branch_id: 30, confirmed: 1,
                                             snapshot_in_pool_in_branch_id: 999,
                                             zfs_path: source_path, zfs_guid: 104,
                                             zfs_owner_fs_guid: 103, physical_presence: 1),
      db('storage_filesystem_identities', 80, node_id: 2, pool_id: 1,
                                              branch_id: 32, zfs_path: clone_path,
                                              path_digest: Digest::SHA256.hexdigest(clone_path.b),
                                              zfs_guid: 105, physical_presence: 1,
                                              origin_state: 1)
    ]
  end

  def zfs_rows
    [
      zfs(root_path, 'filesystem', 100),
      zfs("#{root_path}/vpsadmin", 'filesystem', 200),
      zfs("#{root_path}/vpsadmin/config", 'filesystem', 201),
      zfs("#{root_path}/vpsadmin/download", 'filesystem', 202),
      zfs("#{root_path}/vpsadmin/mount", 'filesystem', 203),
      zfs("#{root_path}/vpsadmin/mount/unknown", 'filesystem', 204),
      zfs("#{root_path}/101", 'filesystem', 101),
      zfs("#{root_path}/101/tree.0", 'filesystem', 102),
      zfs(branch_path, 'filesystem', 103),
      zfs(source_path, 'snapshot', 104, owner_path: branch_path,
                                        owner_guid: '103', clones: [clone_path]),
      zfs(clone_path, 'filesystem', 105, origin: source_path),
      zfs("#{root_path}/orphan@same-guid", 'snapshot', 104,
          owner_path: "#{root_path}/orphan", owner_guid: '106')
    ]
  end

  def write_capture(store, mode:, database: db_rows, physical: zfs_rows, state: 'complete',
                    second_roots: nil, second_zpool_guid: '900')
    db_text = database.map { |item| "#{format.canonical(item)}\n" }.join
    zfs_text = physical.map { |item| "#{format.canonical(item)}\n" }.join
    managed_roots = database.filter_map do |item|
      fields = item.fetch('fields')
      fields.fetch('fields').fetch('filesystem') if fields.fetch('table') == 'pools'
    end.sort
    root_guids = managed_roots.to_h do |path|
      object = physical.find { |item| item.dig('fields', 'path') == path }
      [path, object&.dig('fields', 'guid')]
    end
    manifest = {
      'version' => format::VERSION, 'policy_version' => format::POLICY_VERSION,
      'state' => state, 'confidence' => 'advisory_unguarded',
      'finding_key' => store.key_metadata, 'run_id' => store.run_id.to_s,
      'mode' => mode,
      'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                   'managed_root' => root_path, 'mutation_epoch' => '4' },
      'db' => { 'row_count' => database.size, 'digest' => Digest::SHA256.hexdigest(db_text),
                'confirmation_coverage' => 'selected_chains_only',
                'reference_closure' => 'selected_pool_sips_recursive_sipb_and_clones',
                'managed_roots' => managed_roots },
      'zfs' => {
        'row_count' => physical.size, 'digest' => Digest::SHA256.hexdigest(zfs_text),
        'first' => { 'count' => physical.size, 'digest' => Digest::SHA256.hexdigest(zfs_text),
                     'zpool_guid' => '900', 'roots' => root_guids },
        'second' => { 'count' => physical.size, 'digest' => Digest::SHA256.hexdigest(zfs_text),
                      'zpool_guid' => second_zpool_guid,
                      'roots' => second_roots || root_guids }
      }
    }
    manifest['digest'] = format.digest(manifest)
    store.write('db.jsonl') { |file| file.write(db_text) }
    store.write('zfs.jsonl') { |file| file.write(zfs_text) }
    store.write('manifest.json') { |file| file.write("#{format.canonical(manifest)}\n") }
    manifest
  end

  def actions(store)
    File.readlines(store.path('candidate-actions-v2.jsonl')).map do |line|
      format.parse_line!(line, expected_kind: 'candidate_action').fetch('fields')
    end
  end

  %w[bootstrap steady].each do |mode|
    it "keeps seven finding classes blocked and proposes only a proved physical origin in #{mode}" do
      Dir.mktmpdir do |root|
        store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
        write_capture(store, mode:)
        artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
        report = artifacts.compare!
        legacy = artifacts.dry_run!
        summary = artifacts.plan!
        expect(legacy.fetch('candidate_count')).to eq(report.fetch('findings'))
        expect(summary.fetch('executable_count')).to eq(0)

        rows = actions(store)
        expect(rows.map { |row| row.fetch('finding_code') }).to include(
          'reciprocal_clone_origin_unrepresented', 'disk_only_object',
          'db_only_branch', 'reference_count_surplus_unresolved',
          'sipb_parent_unresolved', 'pending_dataset_create', 'headless_backup_dip'
        )
        expect(rows).to all(include('executable' => false))
        %w[disk_only_object db_only_branch reference_count_surplus_unresolved
           sipb_parent_unresolved pending_dataset_create headless_backup_dip].each do |code|
          expect(rows.select { |row| row['finding_code'] == code })
            .to all(include('disposition' => 'no_action', 'possible_operation' => nil))
        end
        origin = rows.find { |row| row['possible_operation'] == 'set_filesystem_origin' }
        expect(origin).to include('possible_operation' => 'set_filesystem_origin',
                                  'target_kind' => 'StorageFilesystemIdentity',
                                  'target_id' => '80')
        expect(origin.fetch('after_values')).to include(
          'origin_snapshot_in_pool_in_branch_id' => '60', 'origin_state' => '2'
        )
        expect(origin.fetch('after_values')).not_to have_key('snapshot_in_pool_in_branch_id')
        expect(origin.fetch('proof_blockers')).to include('full_node_identity_claims_not_captured')
        expect(origin.fetch('proof_blockers')).not_to include(
          'historical_promotion_proof_not_captured', 'signed_lineage_not_captured'
        )
        claim_checks = origin.fetch('preconditions')
        clone_owner = claim_checks.find do |entry|
          entry['kind'] == 'full_db_owner_absent' && entry['owner_id'] == '32'
        end
        clone_path_check = claim_checks.find do |entry|
          entry['kind'] == 'full_db_node_path_absent' && entry['zfs_path'] == clone_path
        end
        clone_digest_check = claim_checks.find do |entry|
          entry['kind'] == 'full_db_node_path_digest_absent' &&
            entry['path_digest'] == Digest::SHA256.hexdigest(clone_path.b)
        end
        expect([clone_owner, clone_path_check, clone_digest_check])
          .to all(include('exclude_id' => '80'))
        expect(claim_checks).to include(include('kind' => 'catalog_row',
                                                'table' => 'storage_filesystem_identities',
                                                'id' => '80'))
        source_owner = claim_checks.find do |entry|
          entry['kind'] == 'full_db_owner_absent' && entry['owner_id'] == '30'
        end
        source_path_check = claim_checks.find do |entry|
          entry['kind'] == 'full_db_node_path_absent' && entry['zfs_path'] == branch_path
        end
        expect([source_owner, source_path_check]).to all(be_a(Hash))
        expect(source_owner).not_to have_key('exclude_id')
        expect(rows.count { |row| row['possible_operation'] == 'set_filesystem_origin' }).to eq(1)
        expect(rows.map { |row| row['possible_operation'] }).to include('create_filesystem_identity')
        support_paths = %w[vpsadmin vpsadmin/config vpsadmin/download vpsadmin/mount]
                        .map { |suffix| "#{root_path}/#{suffix}" }
        expect(rows.filter_map { |row| row.dig('after_values', 'zfs_path') } & support_paths)
          .to be_empty
        disk = rows.find { |row| row.fetch('finding_code') == 'disk_only_object' }
        expect(disk).to include('target_kind' => nil, 'target_id' => nil,
                                'possible_operation' => nil, 'before_values' => nil,
                                'after_values' => nil)
        expect(format.canonical(summary)).not_to include('tank/backup/orphan')
        expect(rows.map { |row| row.fetch('action_key') }.uniq.size).to eq(rows.size)
      end
    end
  end

  it 'binds a bootstrap origin to separate blocked owner and SIPB identity backfills' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows.reject do |item|
        %w[storage_filesystem_identities snapshot_in_pool_in_branches].include?(item.dig('fields', 'table'))
      end
      database << db('snapshot_in_pool_in_branches', 60, snapshot_in_pool_id: 50,
                                                         branch_id: 30, confirmed: 1,
                                                         snapshot_in_pool_in_branch_id: 999,
                                                         zfs_path: nil, zfs_guid: nil,
                                                         zfs_owner_fs_guid: nil,
                                                         physical_presence: 0)
      write_capture(store, mode: 'bootstrap', database:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      rows = actions(store)
      sipb = rows.find do |item|
        item['possible_operation'] == 'backfill_snapshot_occurrence_identity' &&
          item['target_id'] == '60'
      end
      owner = rows.find do |item|
        item['possible_operation'] == 'create_filesystem_identity' &&
          item['owner_kind'] == 'Branch' && item['owner_id'] == '32'
      end
      source_owner = rows.find do |item|
        item['possible_operation'] == 'create_filesystem_identity' &&
          item['owner_kind'] == 'Branch' && item['owner_id'] == '30'
      end
      origin = rows.find { |item| item['possible_operation'] == 'set_filesystem_origin' }
      expect(sipb.fetch('after_values')).to include(
        'zfs_path' => source_path, 'zfs_guid' => '104',
        'zfs_owner_fs_guid' => '103', 'physical_presence' => '1'
      )
      expect(owner).to include('target_kind' => nil, 'target_id' => nil,
                               'before_values' => nil, 'executable' => false)
      expect(owner.fetch('after_values')).to include(
        'branch_id' => '32', 'zfs_path' => clone_path,
        'zfs_guid' => '105', 'origin_state' => '0'
      )
      expect(owner.fetch('proof_blockers')).to include('full_node_identity_claims_not_captured')
      expect(owner.fetch('preconditions').map { |entry| entry.fetch('kind') }).to include(
        'full_db_owner_absent', 'full_db_node_path_digest_absent'
      )
      expect(origin).to include('target_kind' => 'Branch', 'target_id' => '32',
                                'executable' => false)
      expect(origin.fetch('proof_blockers')).to include('full_node_identity_claims_not_captured')
      expect(origin.fetch('preconditions').map { |entry| entry.fetch('kind') }).to include(
        'full_db_owner_absent', 'full_db_node_path_absent', 'full_db_node_path_digest_absent'
      )
      expect(origin.fetch('dependencies')).to contain_exactly(
        sipb.fetch('action_key'), owner.fetch('action_key'), source_owner.fetch('action_key')
      )
    end
  end

  it 'backfills a unique nonbackup SIP despite a duplicate GUID at another path' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = [
        db('pools', 1, node_id: 2, filesystem: root_path, role: 1),
        db('datasets', 10, full_name: '101', confirmed: 1),
        db('dataset_in_pools', 11, pool_id: 1, dataset_id: 10),
        db('snapshots', 40, dataset_id: 10, name: 'snap', confirmed: 1),
        db('snapshot_in_pools', 50, dataset_in_pool_id: 11,
                                    snapshot_id: 40, reference_count: 0,
                                    zfs_path: nil, zfs_guid: nil,
                                    zfs_owner_fs_guid: nil, physical_presence: 0)
      ]
      physical = [
        zfs(root_path, 'filesystem', 100),
        zfs("#{root_path}/101", 'filesystem', 101),
        zfs("#{root_path}/101@snap", 'snapshot', 104,
            owner_path: "#{root_path}/101", owner_guid: '101'),
        zfs("#{root_path}/other@same-guid", 'snapshot', 104,
            owner_path: "#{root_path}/other", owner_guid: '102')
      ]
      write_capture(store, mode: 'bootstrap', database:, physical:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      candidate = actions(store).find do |item|
        item['possible_operation'] == 'backfill_snapshot_occurrence_identity'
      end
      expect(candidate).to include('target_kind' => 'SnapshotInPool',
                                   'target_id' => '50', 'executable' => false)
      expect(candidate.fetch('before_values')).to include('zfs_guid' => nil)
      expect(candidate.fetch('after_values')).to include('zfs_guid' => '104',
                                                         'zfs_owner_fs_guid' => '101')
    end
  end

  it 'plans from a captured max uint64 snapshot GUID without an exponent mismatch' do
    max_guid = '18446744073709551615'
    original = db_rows.find do |item|
      item.dig('fields', 'table') == 'snapshot_in_pool_in_branches'
    end
    fields = original.fetch('fields').fetch('fields').merge('zfs_guid' => BigDecimal(max_guid))
    row = Struct.new(:id, :attributes_before_type_cast).new(60, fields)
    capture = VpsAdmin::StorageReconciler::DbCapture.new(pool_id: 1, store: nil)
    output = StringIO.new
    capture.instance_variable_set(:@file, output)
    capture.send(:write_record, SnapshotInPoolInBranch, row)
    captured = format.parse_line!(output.string, expected_kind: 'db_object')
    expect(captured.dig('fields', 'fields', 'zfs_guid')).to eq(max_guid)

    database = db_rows.map { |item| item == original ? captured : item }
    physical = zfs_rows.map do |item|
      next item unless item.dig('fields', 'path') == source_path

      format.record('zfs_object', item.fetch('fields').merge('guid' => max_guid))
    end
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_capture(store, mode: 'steady', database:, physical:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!

      expect(actions(store).map { |item| item['possible_operation'] })
        .to include('set_filesystem_origin')
      expect(actions(store).map { |item| item['finding_code'] })
        .not_to include('catalog_guid_mismatch')
    end
  end

  it 'rejects snapshot backfill when two identities claim its owner path' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      owner_path = "#{root_path}/101"
      database = [
        db('pools', 1, node_id: 2, filesystem: root_path, role: 1),
        db('datasets', 10, full_name: '101', confirmed: 1),
        db('dataset_in_pools', 11, pool_id: 1, dataset_id: 10),
        db('snapshots', 40, dataset_id: 10, name: 'snap', confirmed: 1),
        db('snapshot_in_pools', 50, dataset_in_pool_id: 11,
                                    snapshot_id: 40, reference_count: 0),
        db('storage_filesystem_identities', 70, node_id: 2, pool_id: 1,
                                                dataset_in_pool_id: 11, zfs_path: owner_path,
                                                path_digest: Digest::SHA256.hexdigest(owner_path.b),
                                                zfs_guid: 101, physical_presence: 1),
        db('storage_filesystem_identities', 71, node_id: 2, pool_id: 1,
                                                owner_pool_id: 1, zfs_path: owner_path,
                                                path_digest: '0' * 64,
                                                zfs_guid: 101, physical_presence: 1)
      ]
      physical = [
        zfs(root_path, 'filesystem', 100),
        zfs(owner_path, 'filesystem', 101),
        zfs("#{owner_path}@snap", 'snapshot', 104,
            owner_path:, owner_guid: '101')
      ]
      write_capture(store, mode: 'bootstrap', database:, physical:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      expect(actions(store).none? do |item|
        item['possible_operation'] == 'backfill_snapshot_occurrence_identity'
      end).to be(true)
    end
  end

  it 'backfills an existing owner identity with null physical fields' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows + [
        db('storage_filesystem_identities', 81, node_id: 2, pool_id: 1,
                                                owner_pool_id: 1, zfs_path: nil,
                                                zfs_guid: nil, physical_presence: 0,
                                                origin_state: 0)
      ]
      write_capture(store, mode: 'steady', database:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      candidate = actions(store).find do |item|
        item['possible_operation'] == 'backfill_filesystem_identity' &&
          item['owner_kind'] == 'Pool'
      end
      expect(candidate).to include('target_kind' => 'StorageFilesystemIdentity',
                                   'target_id' => '81', 'executable' => false)
      expect(candidate.fetch('after_values')).to include(
        'zfs_path' => root_path, 'zfs_guid' => '100', 'origin_state' => '0'
      )
    end
  end

  it 'requires one exact source occurrence despite duplicate GUIDs and SIPBs' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows + [
        db('snapshot_in_pool_in_branches', 61, snapshot_in_pool_id: 50,
                                               branch_id: 32, confirmed: 1,
                                               zfs_path: "#{clone_path}@snap", zfs_guid: 104,
                                               zfs_owner_fs_guid: 105, physical_presence: 1)
      ]
      physical = zfs_rows + [zfs("#{clone_path}@snap", 'snapshot', 104,
                                 owner_path: clone_path, owner_guid: '105')]
      write_capture(store, mode: 'steady', database:, physical:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      origin = actions(store).find { |item| item['possible_operation'] == 'set_filesystem_origin' }
      expect(origin.fetch('after_values')).to include('origin_snapshot_in_pool_in_branch_id' => '60')
    end
  end

  it 'uses the reassigned SIPB occurrence after a physical promotion' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      promoted_source = "#{clone_path}@snap"
      database = db_rows.reject do |item|
        %w[snapshot_in_pool_in_branches storage_filesystem_identities].include?(item.dig('fields', 'table'))
      end
      database += [
        db('snapshot_in_pool_in_branches', 60, snapshot_in_pool_id: 50,
                                               branch_id: 32, confirmed: 1,
                                               zfs_path: promoted_source, zfs_guid: 104,
                                               zfs_owner_fs_guid: 105, physical_presence: 1),
        db('storage_filesystem_identities', 81, node_id: 2, pool_id: 1,
                                                branch_id: 30, zfs_path: branch_path,
                                                path_digest: Digest::SHA256.hexdigest(branch_path.b),
                                                zfs_guid: 103, physical_presence: 1,
                                                origin_state: 1)
      ]
      physical = zfs_rows.reject do |item|
        [source_path, clone_path, branch_path].include?(item.dig('fields', 'path'))
      end
      physical += [
        zfs(clone_path, 'filesystem', 105),
        zfs(promoted_source, 'snapshot', 104, owner_path: clone_path,
                                              owner_guid: '105', clones: [branch_path]),
        zfs(branch_path, 'filesystem', 103, origin: promoted_source)
      ]
      write_capture(store, mode: 'steady', database:, physical:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      origin = actions(store).find { |item| item['possible_operation'] == 'set_filesystem_origin' }
      expect(origin).to include('target_id' => '81')
      expect(origin.fetch('after_values')).to include('origin_snapshot_in_pool_in_branch_id' => '60')
    end
  end

  it 'keeps a one-sided clone edge and pending 5204 name pair without an action' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows + [
        db('snapshots', 41, dataset_id: 10, name: 'pending (unconfirmed)', confirmed: 0),
        db('snapshot_in_pools', 51, dataset_in_pool_id: 11,
                                    snapshot_id: 41, reference_count: 0),
        db('snapshot_in_pool_in_branches', 62, snapshot_in_pool_id: 51,
                                               branch_id: 30, confirmed: 0)
      ]
      physical = zfs_rows.reject { |item| item.dig('fields', 'path') == source_path }
      physical << zfs(source_path, 'snapshot', 104, owner_path: branch_path,
                                                    owner_guid: '103', clones: [])
      physical << zfs("#{branch_path}@pending", 'snapshot', 107,
                      owner_path: branch_path, owner_guid: '103')
      write_capture(store, mode: 'bootstrap', database:, physical:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      rows = actions(store)
      expect(rows.map { |item| item.fetch('finding_code') }).to include(
        'zfs_clone_edge_mismatch', 'pending_snapshot_possible_pair_unresolved'
      )
      expect(rows.find { |item| item['finding_code'] == 'pending_snapshot_possible_pair_unresolved' })
        .to include('disposition' => 'no_action', 'possible_operation' => nil)
      expect(rows.find { |item| item['finding_code'] == 'zfs_clone_edge_mismatch' })
        .to include('disposition' => 'no_action', 'possible_operation' => nil)
    end
  end

  it 'rejects duplicate owner, raw path and digest claims on the selected node' do
    claims = [
      { branch_id: 32, path: clone_path, digest: Digest::SHA256.hexdigest(clone_path.b) },
      { branch_id: 31, path: clone_path, digest: '0' * 64 },
      { branch_id: 31, path: "#{root_path}/elsewhere",
        digest: Digest::SHA256.hexdigest(clone_path.b) }
    ]
    claims.each do |claim|
      Dir.mktmpdir do |root|
        store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
        database = db_rows + [
          db('storage_filesystem_identities', 81, node_id: 2, pool_id: 1,
                                                  branch_id: claim.fetch(:branch_id),
                                                  zfs_path: claim.fetch(:path),
                                                  path_digest: claim.fetch(:digest),
                                                  zfs_guid: 105, physical_presence: 1,
                                                  origin_state: 1)
        ]
        write_capture(store, mode: 'bootstrap', database:)
        artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
        artifacts.compare!
        artifacts.plan!
        expect(actions(store).count { |item| item['possible_operation'] == 'set_filesystem_origin' })
          .to eq(0)
      end
    end
  end

  it 'rejects a clone owner with a wrong digest for its own exact path' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows.reject do |item|
        item.dig('fields', 'table') == 'storage_filesystem_identities'
      end
      database << db('storage_filesystem_identities', 80, node_id: 2, pool_id: 1,
                                                          branch_id: 32, zfs_path: clone_path,
                                                          path_digest: '0' * 64, zfs_guid: 105,
                                                          physical_presence: 1, origin_state: 1)
      write_capture(store, mode: 'steady', database:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      expect(actions(store).none? { |item| item['possible_operation'] == 'set_filesystem_origin' })
        .to be(true)
    end
  end

  it 'scopes indexed physical path claims to the selected node' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows
      manifest = write_capture(store, mode: 'steady', database:)
      findings = VpsAdmin::StorageReconciler::Comparator.new(
        db_records: database, zfs_records: zfs_rows, manifest:, store:
      ).compare
      other_node = db('storage_filesystem_identities', 81, node_id: 3, pool_id: 2,
                                                           owner_pool_id: 2, zfs_path: clone_path,
                                                           path_digest: Digest::SHA256.hexdigest(clone_path.b),
                                                           zfs_guid: 105, physical_presence: 1,
                                                           origin_state: 1)
      planner = described_class.new(
        db_records: database + [other_node], zfs_records: zfs_rows,
        findings:, manifest:, report: { 'digest' => 'a' * 64 }, store:
      )
      origin_count = planner.actions.count do |item|
        item.dig('fields', 'possible_operation') == 'set_filesystem_origin'
      end
      expect(origin_count).to eq(1)
    end
  end

  it 'binds a captured source owner to its row and excludes it from negative claim checks' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows + [
        db('storage_filesystem_identities', 82, node_id: 2, pool_id: 1,
                                                branch_id: 30, zfs_path: branch_path,
                                                path_digest: Digest::SHA256.hexdigest(branch_path.b),
                                                zfs_guid: 103, physical_presence: 1,
                                                origin_state: 1)
      ]
      write_capture(store, mode: 'steady', database:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      origin = actions(store).find { |item| item['possible_operation'] == 'set_filesystem_origin' }
      claims = origin.fetch('preconditions')
      source_claims = claims.select do |entry|
        entry['owner_id'] == '30' || entry['zfs_path'] == branch_path ||
          (entry['kind'] == 'full_db_node_path_digest_absent' &&
           entry['path_digest'] == Digest::SHA256.hexdigest(branch_path.b))
      end
      expect(source_claims.length).to eq(3)
      expect(source_claims).to all(include('exclude_id' => '82'))
      expect(claims).to include(include('kind' => 'catalog_row',
                                        'table' => 'storage_filesystem_identities',
                                        'id' => '82'))
    end
  end

  it 'rejects a second source-owner path claimant even if its digest is wrong' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows + [
        db('storage_filesystem_identities', 82, node_id: 2, pool_id: 1,
                                                branch_id: 30, zfs_path: branch_path,
                                                path_digest: Digest::SHA256.hexdigest(branch_path.b),
                                                zfs_guid: 103, physical_presence: 1,
                                                origin_state: 1),
        db('storage_filesystem_identities', 83, node_id: 2, pool_id: 1,
                                                branch_id: 31, zfs_path: branch_path,
                                                path_digest: '0' * 64, zfs_guid: 103,
                                                physical_presence: 1, origin_state: 1)
      ]
      write_capture(store, mode: 'steady', database:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      expect(actions(store).none? { |item| item['possible_operation'] == 'set_filesystem_origin' })
        .to be(true)
    end
  end

  it 'refuses a populated SIPB whose source Branch identity contradicts the owner GUID' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows + [
        db('storage_filesystem_identities', 82, node_id: 2, pool_id: 1,
                                                branch_id: 30, zfs_path: branch_path,
                                                zfs_guid: 999, physical_presence: 1,
                                                origin_state: 0)
      ]
      write_capture(store, mode: 'steady', database:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      expect(actions(store).none? { |item| item['possible_operation'] == 'set_filesystem_origin' })
        .to be(true)
    end
  end

  it 'refuses null and populated owner identities that claim both a Branch and a Tree' do
    [{ path: nil, guid: nil, presence: 0 },
     { path: clone_path, guid: 105, presence: 1 }].each do |state|
      Dir.mktmpdir do |root|
        store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
        database = db_rows.reject do |item|
          item.dig('fields', 'table') == 'storage_filesystem_identities'
        end
        database << db('storage_filesystem_identities', 80, node_id: 2, pool_id: 1,
                                                            branch_id: 32, dataset_tree_id: 20,
                                                            zfs_path: state.fetch(:path),
                                                            zfs_guid: state.fetch(:guid),
                                                            physical_presence: state.fetch(:presence),
                                                            origin_state: 0)
        write_capture(store, mode: 'steady', database:)
        artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
        artifacts.compare!
        artifacts.plan!
        operations = actions(store).map { |item| item['possible_operation'] }
        expect(operations).not_to include('set_filesystem_origin', 'backfill_filesystem_identity')
      end
    end
  end

  it 'refuses a duplicate physical occurrence claim at one exact source path' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows + [
        db('snapshot_in_pool_in_branches', 61, snapshot_in_pool_id: 50,
                                               branch_id: 30, confirmed: 1,
                                               zfs_path: source_path, zfs_guid: 104,
                                               zfs_owner_fs_guid: 103, physical_presence: 1)
      ]
      write_capture(store, mode: 'steady', database:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      expect(actions(store).count { |item| item['possible_operation'] == 'set_filesystem_origin' })
        .to eq(0)
    end
  end

  it 'indexes hundreds of distinct source paths and filesystem claims once' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows
      sources = []
      500.times do |index|
        snapshot_id = 1_000 + index
        sip_id = 2_000 + index
        path = "#{branch_path}@bulk#{index}"
        unrelated_path = "#{root_path}/unrelated-#{index}"
        database << db('snapshots', snapshot_id, dataset_id: 10,
                                                 name: "bulk#{index}", confirmed: 1)
        database << db('snapshot_in_pools', sip_id, dataset_in_pool_id: 11,
                                                    snapshot_id:, reference_count: 0)
        database << db('snapshot_in_pool_in_branches', 3_000 + index,
                       snapshot_in_pool_id: sip_id, branch_id: 30,
                       confirmed: 1, zfs_path: path,
                       zfs_guid: 5_000 + index,
                       zfs_owner_fs_guid: 103, physical_presence: 1)
        database << db('storage_filesystem_identities', 4_000 + index, node_id: 2, pool_id: 1,
                                                                       branch_id: 6_000 + index,
                                                                       zfs_path: unrelated_path,
                                                                       path_digest: Digest::SHA256.hexdigest(unrelated_path.b),
                                                                       zfs_guid: 7_000 + index)
        sources << { 'path' => path, 'owner_path' => branch_path,
                     'owner_guid' => '103', 'guid' => (5_000 + index).to_s }
      end
      manifest = write_capture(store, mode: 'steady', database:)
      planner = described_class.new(
        db_records: database, zfs_records: zfs_rows, findings: [],
        manifest:, report: { 'digest' => 'a' * 64 }, store:
      )
      identity_rows = planner.instance_variable_get(:@db).fetch('storage_filesystem_identities')
      allow(planner).to receive(:snapshot_catalog_path).and_call_original
      allow(identity_rows).to receive(:each).and_call_original
      allow(identity_rows).to receive(:values).and_call_original
      allow(identity_rows).to receive(:select).and_call_original

      sources.each_with_index do |source, index|
        planner.send(:source_occurrences, source)
        planner.send(:filesystem_identity_claims, 'Branch', 6_000 + index, 2,
                     "#{root_path}/unrelated-#{index}")
      end

      expect(planner).to have_received(:snapshot_catalog_path).at_most(1_600).times
      expect(identity_rows).to have_received(:each).once
      expect(identity_rows).not_to have_received(:values)
      expect(identity_rows).not_to have_received(:select)
    end
  end

  it 'refuses a second catalog owner claiming the clone path' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      database = db_rows + [db('branches', 33, dataset_tree_id: 20,
                                               name: 'clone', index: 2, head: 0)]
      write_capture(store, mode: 'steady', database:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      expect(actions(store).count { |item| item['possible_operation'] == 'set_filesystem_origin' })
        .to eq(0)
    end
  end

  it 'treats another Pool root as an overlapping owner at the snapshot boundary' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      owner_path = "#{root_path}/101"
      database = [
        db('pools', 1, node_id: 2, filesystem: root_path, role: 1),
        db('pools', 2, node_id: 2, filesystem: owner_path, role: 1),
        db('datasets', 10, full_name: '101', confirmed: 1),
        db('dataset_in_pools', 11, pool_id: 1, dataset_id: 10),
        db('snapshots', 40, dataset_id: 10, name: 'snap', confirmed: 1),
        db('snapshot_in_pools', 50, dataset_in_pool_id: 11,
                                    snapshot_id: 40, reference_count: 0,
                                    zfs_path: nil, zfs_guid: nil,
                                    zfs_owner_fs_guid: nil, physical_presence: 0)
      ]
      physical = [
        zfs(root_path, 'filesystem', 100),
        zfs(owner_path, 'filesystem', 101),
        zfs("#{owner_path}@snap", 'snapshot', 104,
            owner_path:, owner_guid: '101')
      ]
      write_capture(store, mode: 'bootstrap', database:, physical:)
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      artifacts.plan!
      expect(actions(store).none? do |item|
        item['possible_operation'] == 'backfill_snapshot_occurrence_identity'
      end).to be(true)
    end
  end

  it 'separates normal failed intents from prepared, executing and unresolved effects' do
    { '0' => false, '1' => false, '4' => true, '5' => false }.each do |phase, candidate|
      Dir.mktmpdir do |root|
        store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
        database = db_rows + [
          db('storage_mutation_intents', 90, node_catalog_id: 2, phase:),
          db('storage_mutation_targets', 91, storage_mutation_intent_id: 90,
                                             catalog_kind: 'Pool', catalog_id: 1,
                                             expected_path: root_path)
        ]
        write_capture(store, mode: 'steady', database:)
        artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
        artifacts.compare!
        artifacts.plan!
        pool_backfill = actions(store).find do |item|
          item['possible_operation'] == 'create_filesystem_identity' &&
            item['owner_kind'] == 'Pool'
        end
        expect(pool_backfill.nil?).to eq(!candidate)
      end
    end
  end

  it 'refuses identity and origin candidates when two passes disagree on root or zpool GUID' do
    [{ second_roots: { root_path => '999' } },
     { second_zpool_guid: '901' }].each do |difference|
      Dir.mktmpdir do |root|
        store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
        write_capture(store, mode: 'steady', **difference)
        artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
        artifacts.compare!
        expect { artifacts.plan! }
          .to raise_error(described_class::Invalid, 'two-pass inventory proof is incomplete')
        expect(File.exist?(store.path('candidate-actions-v2.jsonl'))).to be(false)
      end
    end
  end

  it 'replays identical v2 bytes and completes an interrupted summary only after verification' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_capture(store, mode: 'steady')
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      interrupted = false
      allow(store).to receive(:write).and_wrap_original do |original, name, &block|
        if name == 'dry-run-v2.json' && !interrupted
          interrupted = true
          raise IOError, 'before summary seal'
        end

        original.call(name, &block)
      end
      expect { artifacts.plan! }.to raise_error(IOError, 'before summary seal')
      first = File.binread(store.path('candidate-actions-v2.jsonl'))
      summary = artifacts.plan!
      expect(artifacts.plan!).to eq(summary)
      expect(File.binread(store.path('candidate-actions-v2.jsonl'))).to eq(first)
      File.open(store.path('candidate-actions-v2.jsonl'), 'a') { |file| file.write("tamper\n") }
      expect { artifacts.plan! }.to raise_error(
        VpsAdmin::StorageReconciler::Artifacts::Invalid,
        'existing report artifact differs from recomputed output'
      )
    end
  end

  it 'changes the HMAC action identity across runs and evidence revisions' do
    Dir.mktmpdir do |root|
      first = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_capture(first, mode: 'steady')
      first_artifacts = VpsAdmin::StorageReconciler::Artifacts.new(first)
      first_artifacts.compare!
      first_artifacts.plan!
      first_origin = actions(first).find { |item| item['possible_operation'] == 'set_filesystem_origin' }

      second = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 2, create: true)
      physical = zfs_rows + [zfs("#{root_path}/new-unknown", 'filesystem', 300)]
      write_capture(second, mode: 'steady', physical:)
      second_artifacts = VpsAdmin::StorageReconciler::Artifacts.new(second)
      second_artifacts.compare!
      second_artifacts.plan!
      second_origin = actions(second).find { |item| item['possible_operation'] == 'set_filesystem_origin' }

      expect(second_origin.fetch('finding_key')).to eq(first_origin.fetch('finding_key'))
      expect(second_origin.fetch('action_key')).not_to eq(first_origin.fetch('action_key'))
      expect(second_origin.fetch('capture_digest')).not_to eq(first_origin.fetch('capture_digest'))
    end
  end

  it 'rejects incomplete or stale captures and an edited v1 report' do
    %w[incomplete stale].each do |state|
      Dir.mktmpdir do |root|
        store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
        write_capture(store, mode: 'bootstrap', state:)
        expect { VpsAdmin::StorageReconciler::Artifacts.new(store).plan! }
          .to raise_error(VpsAdmin::StorageReconciler::Artifacts::Invalid)
      end
    end
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_capture(store, mode: 'bootstrap')
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      report = store.read_json('report-v1.json')
      report['finding_counts'] = {}
      report['digest'] = format.digest(report.except('digest'))
      File.write(store.path('report-v1.json'), "#{format.canonical(report)}\n")
      expect { artifacts.plan! }
        .to raise_error(VpsAdmin::StorageReconciler::Artifacts::Invalid)
    end
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_capture(store, mode: 'bootstrap')
      artifacts = VpsAdmin::StorageReconciler::Artifacts.new(store)
      artifacts.compare!
      File.open(store.path('findings-v1.jsonl'), 'a') { |file| file.write("changed\n") }
      expect { artifacts.plan! }
        .to raise_error(VpsAdmin::StorageReconciler::Artifacts::Invalid)
    end
  end

  it 'rejects missing or mismatched private key material before planning' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      write_capture(store, mode: 'bootstrap')
      key = File.join(root, 'finding-key.bin')
      File.write(key, 'x' * 32)
      File.chmod(0o600, key)
      replaced = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1)
      expect { VpsAdmin::StorageReconciler::Artifacts.new(replaced).plan! }
        .to raise_error(VpsAdmin::StorageReconciler::PrivateStore::Invalid)
      File.unlink(key)
      expect { VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1) }
        .to raise_error(VpsAdmin::StorageReconciler::PrivateStore::Invalid)
    end
  end
end
