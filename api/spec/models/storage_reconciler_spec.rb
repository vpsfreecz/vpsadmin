# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'vpsadmin/storage_reconciler'

RSpec.describe VpsAdmin::StorageReconciler::Comparator do
  let(:format) { VpsAdmin::StorageReconciler::Format }

  def db(table, id, fields)
    normalized_fields = fields.transform_keys(&:to_s).transform_values do |value|
      value.nil? ? nil : value.to_s
    end

    format.record('db_object', {
      'table' => table, 'id' => id.to_s,
      'fields' => normalized_fields
    })
  end

  def zfs(path, type, guid, **fields)
    format.record('zfs_object', {
      'path' => path, 'type' => type, 'guid' => guid.to_s,
      'owner_path' => nil, 'owner_guid' => nil,
      'origin' => nil, 'clones' => [], 'userrefs' => '0',
      'deferred_destroy' => 'off', 'creation' => '1', 'createtxg' => '1'
    }.merge(fields.transform_keys(&:to_s)))
  end

  def fixture
    root = 'tank/backup'
    branch = "#{root}/101/tree.0/branch-head.0"
    source = "#{branch}@snap"
    clone = "#{root}/101/tree.0/branch-clone.1"
    db_rows = [
      db('pools', 1, id: 1, node_id: 2, filesystem: root, role: 2),
      db('datasets', 10, id: 10, full_name: '101', confirmed: 0),
      db('dataset_in_pools', 11, id: 11, pool_id: 1, dataset_id: 10),
      db('dataset_trees', 20, id: 20, dataset_in_pool_id: 11, index: 0, head: 0),
      db('branches', 30, id: 30, dataset_tree_id: 20, name: 'head', index: 0, head: 0),
      db('branches', 31, id: 31, dataset_tree_id: 20, name: 'empty', index: 1, head: 0),
      db('snapshots', 40, id: 40, dataset_id: 10, name: 'snap'),
      db('snapshot_in_pools', 50, id: 50, dataset_in_pool_id: 11,
                                  snapshot_id: 40, reference_count: 2),
      db('snapshot_in_pool_in_branches', 60, id: 60, snapshot_in_pool_id: 50,
                                             branch_id: 30, snapshot_in_pool_in_branch_id: 999, confirmed: 1),
      db('snapshot_in_pool_in_branches', 999, id: 999, snapshot_in_pool_id: 500,
                                              branch_id: 900, snapshot_in_pool_in_branch_id: nil, confirmed: 1)
    ]
    zfs_rows = [
      zfs(root, 'filesystem', 100),
      zfs("#{root}/101", 'filesystem', 101),
      zfs("#{root}/101/tree.0", 'filesystem', 102),
      zfs(branch, 'filesystem', 103),
      zfs(source, 'snapshot', 104, owner_path: branch, owner_guid: '103', clones: [clone]),
      zfs(clone, 'filesystem', 105, origin: source),
      zfs("#{root}/orphan", 'filesystem', 106),
      zfs("#{root}/orphan@same-guid", 'snapshot', 104,
          owner_path: "#{root}/orphan", owner_guid: '106')
    ]
    [db_rows, zfs_rows]
  end

  %w[bootstrap steady].each do |mode|
    it "classifies all seven production finding classes conservatively in #{mode}" do
      Dir.mktmpdir do |root|
        store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
        db_rows, zfs_rows = fixture
        manifest = {
          'mode' => mode,
          'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                       'managed_root' => 'tank/backup', 'mutation_epoch' => '4' },
          'db' => { 'digest' => 'a' * 64, 'confirmation_coverage' => 'selected_chains_only',
                    'reference_closure' => 'selected_pool_sips_recursive_sipb_and_clones' },
          'zfs' => { 'digest' => 'b' * 64 }
        }
        findings = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                       manifest:, store:).compare
        codes = findings.map { |row| row.fetch('fields').fetch('code') }

        expect(codes).to include(
          'reciprocal_clone_origin_unrepresented', 'disk_only_object',
          'db_only_branch', 'reference_count_surplus_unresolved',
          'pending_dataset_create', 'headless_backup_dip'
        )
        expect(codes).not_to include('sipb_parent_unresolved', 'head_tree_branch_count')
        expect(findings.count do |row|
          row.fetch('fields').fetch('code') ==
                  'reciprocal_clone_origin_unrepresented'
        end).to eq(1)
        expect(findings.select { |row| row.fetch('fields').fetch('code') == 'disk_only_object' }
                       .length).to eq(3)
        expect(findings.select { |row| row.fetch('fields').fetch('code') == 'pending_dataset_create' }
                       .first.fetch('fields').fetch('blockers'))
          .to include('historical_create_confirmation_not_captured')
      end
    end
  end

  it 'keeps an unresolved parent separate from a broken foreign key claim' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      db_rows, zfs_rows = fixture
      db_rows.reject! { |row| row.fetch('fields').fetch('id') == '999' }
      manifest = {
        'mode' => 'bootstrap',
        'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                     'managed_root' => 'tank/backup', 'mutation_epoch' => '4' },
        'db' => { 'digest' => 'a' * 64,
                  'reference_closure' => 'selected_pool_sips_recursive_sipb_and_clones' },
        'zfs' => { 'digest' => 'b' * 64 }
      }
      codes = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                  manifest:, store:).compare
                             .map { |row| row.fetch('fields').fetch('code') }
      expect(codes).to include('sipb_parent_unresolved')
      expect(codes).not_to include('broken_db_link')
    end
  end

  it 'reports same-path snapshot, owner and filesystem GUID replacement' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      db_rows, zfs_rows = fixture
      source = 'tank/backup/101/tree.0/branch-head.0@snap'
      db_rows.reject! { |record| record.fetch('fields').fetch('id') == '60' }
      db_rows << db('snapshot_in_pool_in_branches', 60,
                    id: 60, snapshot_in_pool_id: 50, branch_id: 30,
                    snapshot_in_pool_in_branch_id: 999, confirmed: 1,
                    zfs_path: source, zfs_guid: 999, zfs_owner_fs_guid: 888,
                    physical_presence: 1)
      db_rows << db('storage_filesystem_identities', 80,
                    id: 80, pool_id: 1, branch_id: 30,
                    zfs_path: 'tank/backup/101/tree.0/branch-head.0',
                    zfs_guid: 777, physical_presence: 1)
      manifest = {
        'mode' => 'steady',
        'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                     'managed_root' => 'tank/backup', 'mutation_epoch' => '4' },
        'db' => { 'digest' => 'a' * 64 }, 'zfs' => { 'digest' => 'b' * 64 }
      }
      codes = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                  manifest:, store:).compare
                             .map { |row| row.fetch('fields').fetch('code') }
      expect(codes).to include('catalog_guid_mismatch', 'catalog_owner_guid_mismatch')
    end
  end

  it 'rejects a stale origin FK even when the physical edge is reciprocal' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      db_rows, zfs_rows = fixture
      db_rows << db('branches', 32, id: 32, dataset_tree_id: 20,
                                    name: 'clone', index: 1, head: 0)
      db_rows << db('storage_filesystem_identities', 81,
                    id: 81, pool_id: 1, branch_id: 32,
                    zfs_path: 'tank/backup/101/tree.0/branch-clone.1',
                    zfs_guid: 105, physical_presence: 1, origin_state: 2,
                    origin_snapshot_in_pool_in_branch_id: 999)
      manifest = {
        'mode' => 'steady',
        'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                     'managed_root' => 'tank/backup', 'mutation_epoch' => '4' },
        'db' => { 'digest' => 'a' * 64 }, 'zfs' => { 'digest' => 'b' * 64 }
      }
      codes = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                  manifest:, store:).compare
                             .map { |row| row.fetch('fields').fetch('code') }
      expect(codes).to include('clone_origin_link_mismatch')
      expect(codes).not_to include('reciprocal_clone_origin_unrepresented')
    end
  end

  it 'does not compare an external SIP without its own reverse closure' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      db_rows, zfs_rows = fixture
      db_rows << db('pools', 3, id: 3, node_id: 4, filesystem: 'tank/external', role: 2)
      db_rows << db('datasets', 99, id: 99, full_name: 'external', confirmed: 0)
      db_rows << db('dataset_in_pools', 501, id: 501, pool_id: 3, dataset_id: 99)
      db_rows << db('snapshots', 401, id: 401, dataset_id: 99, name: 'snap')
      db_rows << db('snapshot_in_pools', 500,
                    id: 500, dataset_in_pool_id: 501, snapshot_id: 401,
                    reference_count: 99)
      manifest = {
        'mode' => 'bootstrap',
        'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                     'managed_root' => 'tank/backup', 'mutation_epoch' => '4' },
        'db' => { 'digest' => 'a' * 64,
                  'reference_closure' => 'selected_pool_sips_recursive_sipb_and_clones' },
        'zfs' => { 'digest' => 'b' * 64 }
      }
      findings = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                     manifest:, store:).compare
      count_findings = findings.filter do |record|
        record.fetch('fields').fetch('code').start_with?('reference_count_')
      end
      expect(count_findings.map { |record| record.fetch('fields').fetch('subject_id') })
        .to contain_exactly('50')
      pending = findings.filter do |record|
        record.fetch('fields').fetch('code') == 'pending_dataset_create'
      end
      expect(pending.map { |record| record.fetch('fields').fetch('subject_id') })
        .to contain_exactly('10')
    end
  end

  it 'reports selected-root edges escaping to another root but skips unrelated edges there' do
    Dir.mktmpdir do |root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root:, run_id: 1, create: true)
      db_rows, zfs_rows = fixture
      selected_source = 'tank/backup/101/tree.0/branch-head.0@snap'
      outside_clone = 'tank/other/from-selected'
      source_index = zfs_rows.index do |record|
        record.fetch('fields').fetch('path') == selected_source
      end
      source_fields = zfs_rows.fetch(source_index).fetch('fields').dup
      source_fields['clones'] = (source_fields.fetch('clones') + [outside_clone]).sort
      zfs_rows[source_index] = format.record('zfs_object', source_fields)
      zfs_rows.push(
        zfs('tank/other', 'filesystem', 201),
        zfs(outside_clone, 'filesystem', 202, origin: selected_source),
        zfs('tank/other@unrelated', 'snapshot', 203,
            owner_path: 'tank/other', owner_guid: '201', clones: ['tank/other/own-clone']),
        zfs('tank/other/own-clone', 'filesystem', 204, origin: 'tank/other@unrelated')
      )
      manifest = {
        'mode' => 'bootstrap',
        'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                     'managed_root' => 'tank/backup', 'mutation_epoch' => '4' },
        'db' => { 'digest' => 'a' * 64 }, 'zfs' => { 'digest' => 'b' * 64 }
      }
      edges = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                  manifest:, store:).compare
                             .filter do |record|
        record.fetch('fields').fetch('code') == 'reciprocal_clone_origin_unrepresented'
      end
      expect(edges.length).to eq(2)
      expect(edges.map { |record| record.fetch('fields').fetch('evidence').fetch('clone') })
        .to include(outside_clone)
      expect(edges.map { |record| record.fetch('fields').fetch('evidence').fetch('clone') })
        .not_to include('tank/other/own-clone')
    end
  end

  it 'recognizes only the four exact Pool::Create support filesystems' do
    Dir.mktmpdir do |private_root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root: private_root, run_id: 1, create: true)
      pool_root = 'tank/backup'
      support = %w[vpsadmin vpsadmin/config vpsadmin/download vpsadmin/mount]
      db_rows = [db('pools', 1, id: 1, node_id: 2, filesystem: pool_root, role: 1)]
      zfs_rows = [zfs(pool_root, 'filesystem', 100)]
      support.each_with_index do |suffix, index|
        zfs_rows << zfs("#{pool_root}/#{suffix}", 'filesystem', 101 + index)
      end
      zfs_rows << zfs("#{pool_root}/vpsadmin/mount/unknown", 'filesystem', 110)
      zfs_rows << zfs("#{pool_root}/vpsadmin/config@unexpected", 'snapshot', 111,
                      owner_path: "#{pool_root}/vpsadmin/config", owner_guid: '102')
      manifest = {
        'mode' => 'bootstrap',
        'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                     'managed_root' => pool_root, 'mutation_epoch' => '4' },
        'db' => { 'digest' => 'a' * 64 }, 'zfs' => { 'digest' => 'b' * 64 }
      }

      findings = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                     manifest:, store:).compare
      disk_paths = findings.filter_map do |record|
        fields = record.fetch('fields')
        fields.fetch('evidence').fetch('path') if fields.fetch('code') == 'disk_only_object'
      end
      expect(disk_paths).to contain_exactly(
        "#{pool_root}/vpsadmin/mount/unknown", "#{pool_root}/vpsadmin/config@unexpected"
      )
    end
  end

  it 'keeps a fatal 5204 physical snapshot as an unresolved intent correlation' do
    Dir.mktmpdir do |private_root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root: private_root, run_id: 1, create: true)
      pool_root = 'tank/backup'
      physical_path = "#{pool_root}/101@2026-09-25T01:02:03"
      db_rows = [
        db('pools', 1, id: 1, node_id: 2, filesystem: pool_root, role: 1),
        db('datasets', 10, id: 10, full_name: '101', confirmed: 1),
        db('dataset_in_pools', 11, id: 11, pool_id: 1, dataset_id: 10),
        db('snapshots', 40, id: 40, dataset_id: 10,
                            name: '2026-09-25T01:02:03 (unconfirmed)', confirmed: 0),
        db('snapshot_in_pools', 50, id: 50, dataset_in_pool_id: 11, snapshot_id: 40,
                                    confirmed: 0, reference_count: 0),
        db('storage_integrity_scopes', 60, id: 60, scope_key: 'dip:11',
                                           pool_catalog_id: 1, dataset_in_pool_id: 11,
                                           dataset_in_pool_catalog_id: 11),
        db('transaction_chains', 70, id: 70, state: 5),
        db('transactions', 71, id: 71, transaction_chain_id: 70, handle: 5204,
                               node_id: 2, status: 0, done: 1),
        db('storage_mutation_intents', 72, id: 72, transaction_id: 71,
                                           transaction_chain_id: 70, node_catalog_id: 2,
                                           kind: 'snapshot_create', phase: 5,
                                           protocol_version: 1, token: 'd' * 64,
                                           manifest_digest: 'c' * 64),
        db('storage_mutation_intent_scopes', 73, id: 73,
                                                 storage_mutation_intent_id: 72,
                                                 storage_integrity_scope_id: 60),
        db('storage_mutation_targets', 74, id: 74, storage_mutation_intent_id: 72,
                                           storage_mutation_intent_scope_id: 73,
                                           snapshot_in_pool_id: 50, catalog_kind: 'SnapshotInPool',
                                           catalog_id: 50, command_key: '5204',
                                           kind: 'snapshot_create', expected_path: physical_path,
                                           expected_owner_fs_guid: 101),
        db('storage_mutation_attempts', 75, id: 75, storage_mutation_intent_id: 72,
                                            command_key: '5204', direction: 0, state: 3)
      ]
      zfs_rows = [
        zfs(pool_root, 'filesystem', 100),
        zfs("#{pool_root}/101", 'filesystem', 101),
        zfs(physical_path, 'snapshot', 104,
            owner_path: "#{pool_root}/101", owner_guid: '101')
      ]
      manifest = {
        'mode' => 'steady',
        'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                     'managed_root' => pool_root, 'mutation_epoch' => '4' },
        'db' => { 'digest' => 'a' * 64 }, 'zfs' => { 'digest' => 'b' * 64 }
      }
      findings = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                     manifest:, store:).compare
      pending = findings.find do |record|
        record.fetch('fields').fetch('code') == 'pending_snapshot_path_unresolved'
      end.fetch('fields')

      expect(pending.fetch('subject_id')).to eq('50')
      expect(pending.fetch('evidence')).to include(
        'physical_path' => physical_path, 'captured_target_ids' => ['74'],
        'receipt_matches' => false
      )
      expect(pending.fetch('blockers')).to include('unsettled_mutation_intent',
                                                   'signed_command_not_captured')
      expect(findings.map { |record| record.fetch('fields').fetch('code') })
        .not_to include('db_object_missing_on_zfs', 'disk_only_object')

      db_rows.reject! { |record| record.fetch('fields').fetch('table') == 'storage_mutation_targets' }
      unbound = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                    manifest:, store:).compare
      possible = unbound.find do |record|
        record.fetch('fields').fetch('code') == 'pending_snapshot_possible_pair_unresolved'
      end.fetch('fields')
      expect(possible.fetch('subject_kind')).to eq('ZFS')
      expect(possible.fetch('evidence')).to include('catalog_path' => "#{physical_path} (unconfirmed)",
                                                    'physical_path' => physical_path)
      expect(possible.fetch('blockers')).to include('exact_intent_target_not_captured')
      expect(unbound.map { |record| record.fetch('fields').fetch('code') })
        .not_to include('db_object_missing_on_zfs', 'disk_only_object',
                        'pending_snapshot_path_unresolved')

      db_rows << db('storage_mutation_targets', 74, id: 74,
                                                    storage_mutation_intent_id: 72, storage_mutation_intent_scope_id: 73,
                                                    snapshot_in_pool_id: 50, catalog_kind: 'SnapshotInPool', catalog_id: 50,
                                                    command_key: '5204', kind: 'snapshot_create',
                                                    expected_path: "#{pool_root}/101@different")
      conflicting = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                        manifest:, store:).compare
      conflict = conflicting.find do |record|
        record.fetch('fields').fetch('code') == 'pending_snapshot_possible_pair_unresolved'
      end.fetch('fields')
      expect(conflict.fetch('evidence').fetch('other_target_ids')).to eq(['74'])
      expect(conflict.fetch('blockers')).to include('intent_target_binding_conflict')

      db_rows.reject! { |record| record.fetch('fields').fetch('table') == 'storage_mutation_targets' }
      [74, 76].each do |target_id|
        db_rows << db('storage_mutation_targets', target_id, id: target_id,
                                                             storage_mutation_intent_id: 72, storage_mutation_intent_scope_id: 73,
                                                             snapshot_in_pool_id: 50, catalog_kind: 'SnapshotInPool', catalog_id: 50,
                                                             command_key: '5204', kind: 'snapshot_create', expected_path: physical_path)
      end
      ambiguous = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                      manifest:, store:).compare
      ambiguity = ambiguous.find do |record|
        record.fetch('fields').fetch('code') == 'pending_snapshot_path_unresolved'
      end.fetch('fields')
      expect(ambiguity.fetch('evidence').fetch('captured_target_ids')).to eq(%w[74 76])
      expect(ambiguity.fetch('blockers')).to include('unique_intent_not_proved')

      db_rows.reject! do |record|
        %w[storage_mutation_targets storage_mutation_attempts storage_mutation_intents]
          .include?(record.fetch('fields').fetch('table'))
      end
      db_rows.push(
        db('storage_mutation_intents', 72, id: 72, transaction_id: 71,
                                           transaction_chain_id: 70, node_catalog_id: 2,
                                           kind: 'snapshot_create', phase: 2,
                                           protocol_version: 1, token: 'd' * 64,
                                           manifest_digest: 'c' * 64),
        db('storage_mutation_targets', 74, id: 74, storage_mutation_intent_id: 72,
                                           storage_mutation_intent_scope_id: 73,
                                           snapshot_in_pool_id: 50, catalog_kind: 'SnapshotInPool',
                                           catalog_id: 50, command_key: '5204',
                                           kind: 'snapshot_create', expected_path: physical_path,
                                           expected_owner_fs_guid: 101),
        db('storage_mutation_attempts', 75, id: 75, storage_mutation_intent_id: 72,
                                            command_key: '5204', direction: 0, state: 1,
                                            finished_at: '2026-09-25T01:02:04Z'),
        db('storage_mutation_target_observations', 76, id: 76,
                                                       storage_mutation_attempt_id: 75,
                                                       storage_mutation_target_id: 74,
                                                       before_presence: 2, after_presence: 1,
                                                       after_path_digest: Digest::SHA256.hexdigest(physical_path),
                                                       before_owner_fs_guid: 101,
                                                       after_owner_fs_guid: 101, after_guid: 104)
      )
      receipt = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                    manifest:, store:).compare.find do |record|
        record.fetch('fields').fetch('code') == 'pending_snapshot_path_unresolved'
      end.fetch('fields')
      expect(receipt.fetch('evidence').fetch('receipt_matches')).to be(true)
      expect(receipt.fetch('blockers')).to include('signed_command_not_captured')
      expect(receipt.fetch('blockers')).not_to include('settled_receipt_not_matching')

      observation = db_rows.pop.fetch('fields')
      db_rows << format.record('db_object', {
        'table' => 'storage_mutation_target_observations', 'id' => '76',
        'fields' => observation.fetch('fields').merge('after_guid' => '999')
      })
      mismatch = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                     manifest:, store:).compare.find do |record|
        record.fetch('fields').fetch('code') == 'pending_snapshot_path_unresolved'
      end.fetch('fields')
      expect(mismatch.fetch('evidence').fetch('receipt_matches')).to be(false)
      expect(mismatch.fetch('blockers')).to include('settled_receipt_not_matching')
    end
  end

  it 'keeps an opaque backup 5204 name difference as a possible pair, not a proven owner' do
    Dir.mktmpdir do |private_root|
      store = VpsAdmin::StorageReconciler::PrivateStore.new(root: private_root, run_id: 1, create: true)
      pool_root = 'tank/backup'
      branch = "#{pool_root}/101/tree.0/branch-head.0"
      physical_path = "#{branch}@2026-09-25T01:02:03"
      db_rows = [
        db('pools', 1, id: 1, node_id: 2, filesystem: pool_root, role: 2),
        db('datasets', 10, id: 10, full_name: '101', confirmed: 1),
        db('dataset_in_pools', 11, id: 11, pool_id: 1, dataset_id: 10),
        db('dataset_trees', 20, id: 20, dataset_in_pool_id: 11, index: 0, head: 1),
        db('branches', 30, id: 30, dataset_tree_id: 20, name: 'head', index: 0, head: 1),
        db('snapshots', 40, id: 40, dataset_id: 10,
                            name: '2026-09-25T01:02:03 (unconfirmed)', confirmed: 0),
        db('snapshot_in_pools', 50, id: 50, dataset_in_pool_id: 11,
                                    snapshot_id: 40, confirmed: 0, reference_count: 0),
        db('snapshot_in_pool_in_branches', 60, id: 60, snapshot_in_pool_id: 50,
                                               branch_id: 30, confirmed: 0)
      ]
      zfs_rows = [
        zfs(pool_root, 'filesystem', 100),
        zfs("#{pool_root}/101", 'filesystem', 101),
        zfs("#{pool_root}/101/tree.0", 'filesystem', 102),
        zfs(branch, 'filesystem', 103),
        zfs(physical_path, 'snapshot', 104, owner_path: branch, owner_guid: '103')
      ]
      manifest = {
        'mode' => 'bootstrap',
        'scope' => { 'node_id' => '2', 'pool_id' => '1', 'zpool' => 'tank',
                     'managed_root' => pool_root, 'mutation_epoch' => '4' },
        'db' => { 'digest' => 'a' * 64 }, 'zfs' => { 'digest' => 'b' * 64 }
      }
      findings = described_class.new(db_records: db_rows, zfs_records: zfs_rows,
                                     manifest:, store:).compare
      candidate = findings.find do |record|
        record.fetch('fields').fetch('code') == 'pending_snapshot_possible_pair_unresolved'
      end.fetch('fields')

      expect(candidate.fetch('subject_kind')).to eq('ZFS')
      expect(candidate.fetch('subject_id')).to match(/\A[0-9a-f]{64}\z/)
      expect(candidate.fetch('subject_id')).not_to eq(format.digest(physical_path))
      expect(candidate.fetch('evidence')).to include('catalog_id' => '60',
                                                     'physical_path' => physical_path)
      expect(candidate.fetch('blockers')).to include('exact_intent_target_not_captured',
                                                     'no_catalog_owner_proof')
      expect(findings.map { |record| record.fetch('fields').fetch('code') })
        .not_to include('db_object_missing_on_zfs', 'disk_only_object')
    end
  end
end
