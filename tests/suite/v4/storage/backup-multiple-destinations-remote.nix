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
    name = "storage-backup-multiple-destinations-remote";

    description = ''
      Create a VPS with two remote backup destinations, let one destination lag
      behind, and verify source rotation keeps the shared snapshot needed for
      the lagging destination.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote backups with multiple destinations', order: :defined do
        it 'creates a VPS with one primary pool and two backup pools' do
          @setup = create_remote_backup_vps_with_backups(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-multi-dest',
            primary_pool_fs: primary_pool_fs,
            backup_pool_defs: [
              { label: 'backup-a', filesystem: 'tank/backup-a' },
              { label: 'backup-b', filesystem: 'tank/backup-b' }
            ]
          )
        end

        it 'keeps the shared source snapshot needed by a lagging remote destination' do
          dst_a = @setup.fetch('dst_dip_ids').fetch('backup-a')
          dst_b = @setup.fetch('dst_dip_ids').fetch('backup-b')

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
            label: 'multi-dest-s1'
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
            dst_dip_id: dst_b
          )

          @snap2 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'multi-dest-s2'
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
            dst_dip_id: dst_b
          )

          @snap3 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'multi-dest-s3'
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_b
          )

          source_names = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).map { |row| row.fetch('name') }

          expect(source_names).to include(@snap2.fetch('name'), @snap3.fetch('name'))
          expect(source_names).not_to include(@snap1.fetch('name'))

          catch_up = fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_a
          )
          handles = chain_transactions(services, catch_up.fetch('chain_id')).map { |row| row.fetch('handle') }

          expect(branch_rows_for_dip(services, dst_a).count).to eq(1)
          expect(head_tree_row(services, dst_a).fetch('tree_index')).to eq(0)
          expect(handles).to include(
            tx_types(services).fetch('send'),
            tx_types(services).fetch('recv'),
            tx_types(services).fetch('recv_check')
          )
          expect(handles).not_to include(tx_types(services).fetch('local_send'))
          expect(handles).not_to include(tx_types(services).fetch('create_tree'))
          expect(handles).not_to include(tx_types(services).fetch('branch_dataset'))
          expect(handles.count { |handle| handle == tx_types(services).fetch('send') }).to eq(1)
          expect(handles.count { |handle| handle == tx_types(services).fetch('recv') }).to eq(1)
          expect(handles.count { |handle| handle == tx_types(services).fetch('recv_check') }).to eq(1)
        end
      end
    '';
  }
)
