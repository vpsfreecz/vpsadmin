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
    name = "storage-restore-after-reinstall-remote";

    description = ''
      Create remote backups on a second node, reinstall the VPS to drop primary
      snapshot history, restore from a snapshot that exists only on backup, and
      verify later backups remain incrementally usable.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'restore after reinstall from remote backup', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-remote-reinstall',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'creates remote backup history and reinstalls the VPS' do
          @snap1 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'remote-reinstall-1'
          )
          @snap2 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'remote-reinstall-2'
          )

          @history_before_reinstall = current_history_id(services, @setup.fetch('dataset_id'))

          reinstall = reinstall_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: @setup.fetch('vps_id')
          )
          @reinstall_chain_id = reinstall.fetch('chain_id')

          services.wait_for_chain_state(@reinstall_chain_id, state: :done)

          wait_until_block_succeeds(name: 'local snapshots removed after reinstall') do
            snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).empty?
          end

          expect(current_history_id(services, @setup.fetch('dataset_id'))).to eq(@history_before_reinstall + 1)
        end

        it 'restores from backup-only history over the remote send/recv rollback path' do
          restore = rollback_dataset_to_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            snapshot_id: @snap2.fetch('id')
          )
          @restore_chain_id = restore.fetch('chain_id')

          services.wait_for_chain_state(@restore_chain_id, state: :done)
          wait_for_vps_running(services, @setup.fetch('vps_id'))

          restore_handles = chain_transactions(services, @restore_chain_id).map { |row| row.fetch('handle') }
          primary_snapshot_names = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).map { |row| row.fetch('name') }

          expect(restore_handles).to include(
            @tx_types.fetch('prepare_rollback'),
            @tx_types.fetch('send'),
            @tx_types.fetch('recv'),
            @tx_types.fetch('recv_check'),
            @tx_types.fetch('apply_rollback')
          )
          expect(restore_handles).not_to include(@tx_types.fetch('local_send'))
          expect(primary_snapshot_names).to include(@snap2.fetch('name'))
          expect(head_tree_row(services, @setup.fetch('dst_dip_id'))).not_to be_nil
          expect(head_branch_row(services, @setup.fetch('dst_dip_id'))).not_to be_nil
        end

        it 'keeps the restored backup history incrementally usable for future backups' do
          @snap3 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'remote-reinstall-3'
          )

          services.wait_for_tree_count(@setup.fetch('dst_dip_id'), count: 1)

          branches = branch_rows_for_dip(services, @setup.fetch('dst_dip_id'))
          entries = branch_entries_for_dip(services, @setup.fetch('dst_dip_id'))
          head_branch = branches.find { |row| row.fetch('head') == 1 }
          s3_entry = entries.find { |row| row.fetch('snapshot_name') == @snap3.fetch('name') }
          backup_handles = chain_transactions(services, @snap3.fetch('chain_id')).map { |row| row.fetch('handle') }

          expect(branches.count).to eq(1)
          expect(s3_entry.fetch('branch_id')).to eq(head_branch.fetch('id'))
          expect(backup_handles).to include(
            @tx_types.fetch('send'),
            @tx_types.fetch('recv'),
            @tx_types.fetch('recv_check')
          )
          expect(backup_handles).not_to include(@tx_types.fetch('local_send'))
          expect(
            node2.zfs_exists?(
              "#{branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), head_branch)}@#{@snap3.fetch('name')}",
              type: 'snapshot',
              timeout: 30
            )
          ).to be(true)
        end
      end
    '';
  }
)
