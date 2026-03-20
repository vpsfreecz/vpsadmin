import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-2-node.nix;
    node1Seed = clusterSeed.nodes.node1;
    node2Seed = clusterSeed.nodes.node2;
    common = import ./remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = node1Seed.id;
      node2Id = node2Seed.id;
    };
  in
  {
    name = "storage-topology-reconciliation";

    description = ''
      Create a simple remote rollback topology, compare the backup dependency
      graph stored in the database with the real ZFS origin/clone topology on
      the backup node, and verify they match in the one-rollback case.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'DB and ZFS topology reconciliation', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-topology',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'builds a simple rollback topology on the remote backup dataset' do
          @snap1 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'topology-1'
          )
          @snap2 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'topology-2'
          )
          @snap3 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'topology-3'
          )

          rollback = rollback_dataset_to_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            snapshot_id: @snap2.fetch('id')
          )

          services.wait_for_chain_state(rollback.fetch('chain_id'), state: :done)
          services.wait_for_branch_count(@setup.fetch('dst_dip_id'), count: 2)
          wait_for_vps_running(services, @setup.fetch('vps_id'))

          @snap4 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'topology-4'
          )
        end

        it 'keeps DB dependency metadata aligned with ZFS origin and clone state' do
          branches = branch_rows_for_dip(services, @setup.fetch('dst_dip_id'))
          entries = branch_entries_for_dip(services, @setup.fetch('dst_dip_id'))
          new_head = branches.find { |row| row.fetch('head') == 1 }
          old_branch = branches.find { |row| row.fetch('head') == 0 }
          s2_entry = entries.find do |row|
            row.fetch('snapshot_name') == @snap2.fetch('name') && row.fetch('branch_id') == new_head.fetch('id')
          end
          s3_entry = entries.find do |row|
            row.fetch('snapshot_name') == @snap3.fetch('name') && row.fetch('branch_id') == old_branch.fetch('id')
          end

          origin = node2.zfs_get(
            fs: branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), old_branch),
            property: 'origin',
            timeout: 30
          ).last
          clones = node2.zfs_get(
            fs: "#{branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), new_head)}@#{@snap2.fetch('name')}",
            property: 'clones',
            timeout: 30
          ).last.split(',').reject(&:empty?)
          dependent_count = entries.count { |row| row.fetch('parent_entry_id') == s2_entry.fetch('entry_id') }

          expect(branches.count).to eq(2)
          expect(origin).to eq("#{branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), new_head)}@#{@snap2.fetch('name')}")
          expect(clones).to include(branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), old_branch))
          expect(s3_entry.fetch('parent_entry_id')).to eq(s2_entry.fetch('entry_id'))
          expect(s2_entry.fetch('reference_count')).to eq(dependent_count)
          expect(s2_entry.fetch('reference_count')).to eq(1)
        end
      end
    '';
  }
)
