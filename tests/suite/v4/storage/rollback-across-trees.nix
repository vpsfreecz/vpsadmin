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
    name = "storage-rollback-across-trees";

    description = ''
      Create backup history divergence on a remote backup, roll back to a
      snapshot from the previous tree, and verify future backups continue
      incrementally on the selected tree.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'rollback across backup trees', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-rollback-across-trees',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'switches the backup head tree and keeps future backups incremental' do
          @snap1 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'rollback-tree-s1'
          )
          @snap2 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'rollback-tree-s2'
          )

          reinstall = reinstall_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: @setup.fetch('vps_id')
          )
          services.wait_for_chain_state(reinstall.fetch('chain_id'), state: :done)

          wait_until_block_succeeds(name: 'local snapshots removed after reinstall for rollback-across-trees') do
            snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).empty?
          end

          @snap3 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'rollback-tree-s3'
          )
          @snap4 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'rollback-tree-s4'
          )

          report_before = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          )

          expect(report_before.fetch('db').fetch('trees').count).to eq(2)
          expect(head_tree_row(services, @setup.fetch('dst_dip_id')).fetch('tree_index')).to eq(1)

          rollback = rollback_dataset_to_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            snapshot_id: @snap2.fetch('id')
          )
          services.wait_for_chain_state(rollback.fetch('chain_id'), state: :done)
          wait_for_vps_running(services, @setup.fetch('vps_id'))

          rollback_handles = chain_transactions(services, rollback.fetch('chain_id')).map { |row| row.fetch('handle') }

          expect(rollback_handles).to include(
            @tx_types.fetch('send'),
            @tx_types.fetch('recv'),
            @tx_types.fetch('recv_check')
          )
          expect(rollback_handles).not_to include(@tx_types.fetch('local_send'))
          expect(head_tree_row(services, @setup.fetch('dst_dip_id')).fetch('tree_index')).to eq(0)
          expect(head_branch_row(services, @setup.fetch('dst_dip_id')).fetch('tree_index')).to eq(0)
          expect(
            branch_rows_for_dip(services, @setup.fetch('dst_dip_id')).count do |row|
              row.fetch('tree_index') == 0 && row.fetch('head') == 1
            end
          ).to eq(1)

          @snap5 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'rollback-tree-s5'
          )

          backup_handles = chain_transactions(services, @snap5.fetch('chain_id')).map { |row| row.fetch('handle') }
          report_after = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          )
          head_branch = head_branch_row(services, @setup.fetch('dst_dip_id'))
          head_branch_entries = report_after.fetch('db').fetch('entries').select do |row|
            row.fetch('tree_index') == 0 && row.fetch('branch_id') == head_branch.fetch('branch_id')
          end
          snapshot_names = report_after.fetch('db').fetch('entries').map { |row| row.fetch('snapshot_name') }

          expect(report_after.fetch('db').fetch('trees').count).to eq(2)
          expect(head_tree_row(services, @setup.fetch('dst_dip_id')).fetch('tree_index')).to eq(0)
          expect(backup_handles).to include(
            @tx_types.fetch('send'),
            @tx_types.fetch('recv'),
            @tx_types.fetch('recv_check')
          )
          expect(backup_handles).not_to include(@tx_types.fetch('local_send'))
          expect(backup_handles).not_to include(@tx_types.fetch('create_tree'))
          expect(backup_handles).not_to include(@tx_types.fetch('branch_dataset'))
          expect(head_branch_entries.map { |row| row.fetch('snapshot_name') }).to include(@snap5.fetch('name'))

          report_after.fetch('db').fetch('entries').each do |entry|
            descendant_count = report_after.fetch('db').fetch('entries').count do |candidate|
              candidate.fetch('parent_entry_id') == entry.fetch('entry_id')
            end

            expect(entry.fetch('reference_count')).to eq(descendant_count)
          end

          report_after.fetch('zfs').fetch('origins').each_value do |origin|
            next if origin.nil? || origin.empty? || origin == '-'

            expect(snapshot_names).to include(origin.split('@', 2).last)
          end
        end
      end
    '';
  }
)
