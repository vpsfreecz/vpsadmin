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
    name = "storage-rollback-from-remote-backup";

    description = ''
      Back up multiple snapshots of a VPS root dataset to a backup pool on the
      second node, roll back to an older snapshot, verify backup branching
      metadata, and confirm later backups continue on the new head branch.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'rollback from remote backup', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-remote-rollback',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'builds remote backup history and rolls back to the middle snapshot' do
          @snapshots = []

          3.times do |i|
            @snapshots << create_and_backup_snapshot(
              services,
              admin_user_id: admin_user_id,
              dataset_id: @setup.fetch('dataset_id'),
              src_dip_id: @setup.fetch('src_dip_id'),
              dst_dip_id: @setup.fetch('dst_dip_id'),
              label: "remote-rollback-#{i + 1}"
            )
          end

          @history_before = current_history_id(services, @setup.fetch('dataset_id'))

          rollback = rollback_dataset_to_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            snapshot_id: @snapshots[1].fetch('id')
          )
          @rollback_chain_id = rollback.fetch('chain_id')

          services.wait_for_chain_state(@rollback_chain_id, state: :done)
          services.wait_for_branch_count(@setup.fetch('dst_dip_id'), count: 2)
          wait_for_vps_running(services, @setup.fetch('vps_id'))
        end

        it 'records rollback branching on the remote backup dataset' do
          branches = branch_rows_for_dip(services, @setup.fetch('dst_dip_id'))
          entries = branch_entries_for_dip(services, @setup.fetch('dst_dip_id'))
          new_head = branches.find { |row| row.fetch('head') == 1 }
          old_branch = branches.find { |row| row.fetch('head') == 0 }
          s2_entry = entries.find { |row| row.fetch('snapshot_name') == @snapshots[1].fetch('name') }
          s3_entry = entries.find { |row| row.fetch('snapshot_name') == @snapshots[2].fetch('name') }
          rollback_handles = chain_transactions(services, @rollback_chain_id).map { |row| row.fetch('handle') }

          expect(branches.count).to eq(2)
          expect(new_head.fetch('name')).to eq(@snapshots[1].fetch('name'))
          expect(old_branch.fetch('head')).to eq(0)
          expect(s3_entry.fetch('parent_entry_id')).to eq(s2_entry.fetch('entry_id'))
          expect(s2_entry.fetch('reference_count')).to be >= 1
          expect(current_history_id(services, @setup.fetch('dataset_id'))).to eq(@history_before + 1)
          expect(rollback_handles).to include(@tx_types.fetch('branch_dataset'))
          expect(rollback_handles).not_to include(@tx_types.fetch('local_send'))
          expect(
            node2.zfs_exists?(
              branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), old_branch),
              type: 'filesystem',
              timeout: 30
            )
          ).to be(true)

          @head_branch_id = new_head.fetch('id')
        end

        it 'continues future backups on the new head branch over the remote send path' do
          @snap4 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'remote-rollback-4'
          )

          branches = branch_rows_for_dip(services, @setup.fetch('dst_dip_id'))
          entries = branch_entries_for_dip(services, @setup.fetch('dst_dip_id'))
          current_head = branches.find { |row| row.fetch('head') == 1 }
          s4_entry = entries.find { |row| row.fetch('snapshot_name') == @snap4.fetch('name') }
          backup_handles = chain_transactions(services, @snap4.fetch('chain_id')).map { |row| row.fetch('handle') }

          expect(current_head.fetch('id')).to eq(@head_branch_id)
          expect(branches.count).to eq(2)
          expect(s4_entry.fetch('branch_id')).to eq(@head_branch_id)
          expect(backup_handles).to include(
            @tx_types.fetch('send'),
            @tx_types.fetch('recv'),
            @tx_types.fetch('recv_check')
          )
          expect(backup_handles).not_to include(@tx_types.fetch('local_send'))
        end
      end
    '';
  }
)
