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
    name = "storage-backup-multiple-destinations-diverged-remote";

    description = ''
      Rebuild one remote backup destination into a new history while another
      destination is still lagging on the old history, and verify source-side
      retention preserves incremental catch-up for the lagging destination.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote backups with diverged multiple destinations', order: :defined do
        it 'creates a VPS with one primary pool and two backup pools' do
          @setup = create_remote_backup_vps_with_backups(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-multi-dest-diverged',
            primary_pool_fs: primary_pool_fs,
            backup_pool_defs: [
              { label: 'backup-a', filesystem: 'tank/backup-a' },
              { label: 'backup-b', filesystem: 'tank/backup-b' }
            ]
          )
        end

        it 'preserves incremental viability for the lagging destination after the other destination is rebuilt' do
          dst_a = @setup.fetch('dst_dip_ids').fetch('backup-a')
          dst_b_old = @setup.fetch('dst_dip_ids').fetch('backup-b')
          backup_b_pool_id = @setup.fetch('backup_pool_ids').fetch('backup-b')
          backup_b_path = @setup.fetch('backup_dataset_paths').fetch('backup-b')

          set_snapshot_retention(
            services,
            dip_id: @setup.fetch('src_dip_id'),
            min_snapshots: 1,
            max_snapshots: 1,
            snapshot_max_age: 0
          )

          @snap1 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'multi-dest-diverged-s1'
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_a
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_b_old
          )

          @snap2 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'multi-dest-diverged-s2'
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_a
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_b_old
          )

          @snap3 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'multi-dest-diverged-s3'
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_b_old
          )

          source_names = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).map { |row| row.fetch('name') }

          expect(source_names).to include(@snap2.fetch('name'), @snap3.fetch('name'))
          expect(source_names).not_to include(@snap1.fetch('name'))

          destroy_response = destroy_backup_dataset(
            services,
            admin_user_id: admin_user_id,
            dip_id: dst_b_old
          )
          wait_for_chain_states_local(
            services,
            destroy_response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )

          destroy_state = services.mysql_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{destroy_response.fetch('chain_id')}"
          ).to_i
          destroy_failures = chain_failure_details(services, destroy_response.fetch('chain_id'))

          expect(destroy_state).to eq(services.class::CHAIN_STATES[:done]), destroy_failures.inspect
          expect(destroy_failures).to eq([]), destroy_failures.inspect
          expect(node2.zfs_exists?(backup_b_path, type: 'filesystem', timeout: 30)).to be(false)

          recreated = ensure_dataset_in_pool(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            pool_id: backup_b_pool_id
          )
          dst_b = recreated.fetch('dataset_in_pool_id')

          wait_until_block_succeeds(name: 'backup-b dataset recreated') do
            node2.zfs_exists?(backup_b_path, type: 'filesystem', timeout: 30)
          end

          @snap4 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'multi-dest-diverged-s4'
          )
          rebuild = fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_b
          )
          rebuild_handles = chain_transactions(services, rebuild.fetch('chain_id')).map { |row| row.fetch('handle') }
          rebuild_failures = chain_failure_details(services, rebuild.fetch('chain_id'))

          source_names_before_catch_up = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).map { |row| row.fetch('name') }

          expect(source_names_before_catch_up).to include(@snap2.fetch('name'))
          expect(rebuild_handles).to include(
            @tx_types.fetch('create_tree'),
            @tx_types.fetch('send'),
            @tx_types.fetch('recv'),
            @tx_types.fetch('recv_check')
          )
          expect(rebuild_handles).not_to include(@tx_types.fetch('local_send'))
          expect(branch_rows_for_dip(services, dst_b).count).to eq(1)
          expect(head_tree_row(services, dst_b).fetch('tree_index')).to eq(0)
          expect(rebuild_failures).to eq([]), rebuild_failures.inspect

          catch_up = fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_a
          )
          catch_up_handles = chain_transactions(services, catch_up.fetch('chain_id')).map { |row| row.fetch('handle') }
          catch_up_failures = chain_failure_details(services, catch_up.fetch('chain_id'))
          dst_a_names = snapshot_rows_for_dip(services, dst_a).map { |row| row.fetch('name') }
          dst_b_names = snapshot_rows_for_dip(services, dst_b).map { |row| row.fetch('name') }

          expect(catch_up_handles).to include(
            @tx_types.fetch('send'),
            @tx_types.fetch('recv'),
            @tx_types.fetch('recv_check')
          )
          expect(catch_up_handles).not_to include(@tx_types.fetch('create_tree'))
          expect(catch_up_handles).not_to include(@tx_types.fetch('branch_dataset'))
          expect(catch_up_handles).not_to include(@tx_types.fetch('local_send'))
          expect(branch_rows_for_dip(services, dst_a).count).to eq(1)
          expect(dst_a_names).to include(@snap4.fetch('name'))
          expect(dst_b_names).to include(@snap4.fetch('name'))
          expect(catch_up_failures).to eq([]), catch_up_failures.inspect
        end
      end
    '';
  }
)
