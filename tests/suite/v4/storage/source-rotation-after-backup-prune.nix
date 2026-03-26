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
    name = "storage-source-rotation-after-backup-prune";

    description = ''
      Prune an old backup-side snapshot, rotate the source dataset, and verify
      obsolete source snapshots are released once a newer shared backup
      snapshot still preserves incremental history.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'source rotation after backup prune', order: :defined do
        it 'creates a dataset with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_dataset(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            dataset_name: 'storage-source-rotation-after-prune',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'rotates away obsolete source snapshots after their old backup copy is pruned' do
          storage_types = storage_tx_types(services)
          snap1 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'source-rotation-after-prune-s1'
          )
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'source-rotation-after-prune-s2'
          )
          snap3 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'source-rotation-after-prune-s3'
          )

          oldest_backup = snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id')).first
          prune = destroy_snapshot_in_pool(
            services,
            admin_user_id: admin_user_id,
            sip_id: oldest_backup.fetch('snapshot_in_pool_id')
          )
          prune_state = services.mysql_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{prune.fetch('chain_id')}"
          ).to_i
          prune_failures = chain_failure_details(services, prune.fetch('chain_id'))

          expect(prune_state).to eq(services.class::CHAIN_STATES[:done]), prune_failures.inspect
          wait_for_snapshot_names(
            services,
            dip_id: @setup.fetch('dst_dip_id'),
            exclude_names: [oldest_backup.fetch('name')]
          )

          set_snapshot_retention(
            services,
            dip_id: @setup.fetch('src_dip_id'),
            min_snapshots: 1,
            max_snapshots: 1,
            snapshot_max_age: 0
          )

          rotation = rotate_dataset(
            services,
            admin_user_id: admin_user_id,
            dip_id: @setup.fetch('src_dip_id')
          )
          rotation_state = services.mysql_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{rotation.fetch('chain_id')}"
          ).to_i
          rotation_failures = chain_failure_details(services, rotation.fetch('chain_id'))
          source_names = wait_for_snapshot_names(
            services,
            dip_id: @setup.fetch('src_dip_id'),
            exclude_names: [snap1.fetch('name')]
          )
          backup_names = snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id')).map { |row| row.fetch('name') }
          shared_names = source_names & backup_names

          expect(rotation_state).to eq(services.class::CHAIN_STATES[:done]), rotation_failures.inspect
          expect(source_names).not_to include(snap1.fetch('name'))
          expect(shared_names).to include(snap3.fetch('name'))

          snap4 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'source-rotation-after-prune-s4'
          )
          backup_names_after = wait_for_snapshot_names(
            services,
            dip_id: @setup.fetch('dst_dip_id'),
            include_names: [snap4.fetch('name')]
          )
          handles = chain_transactions(services, snap4.fetch('chain_id')).map { |tx| tx.fetch('handle') }

          expect(backup_names_after).to include(snap3.fetch('name'))
          expect(backup_names_after).to include(snap4.fetch('name'))
          expect(handles).not_to include(storage_types.fetch('create_tree'))
        end
      end
    '';
  }
)
