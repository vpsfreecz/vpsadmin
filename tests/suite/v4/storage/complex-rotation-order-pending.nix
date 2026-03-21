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
    name = "storage-complex-rotation-order-pending";

    description = ''
      Build a complex multi-tree remote backup topology, run aggressive
      rotation, and keep the desired dependency-safe rotation behaviour as a
      real pending contract.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'rotating a complex multi-tree backup topology', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-complex-rotation',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'keeps a pending contract for dependency-safe aggressive rotation across tree switches' do
          build_complex_multi_tree_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            vps_id: @setup.fetch('vps_id'),
            label_prefix: 'complex-rotation'
          )

          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'complex-rotation-s11'
          )
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'complex-rotation-s12'
          )

          count_before = snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id')).count
          branch_count_before = branch_rows_for_dip(services, @setup.fetch('dst_dip_id')).count
          tree_count_before = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          ).fetch('db').fetch('trees').count

          set_snapshot_retention(
            services,
            dip_id: @setup.fetch('dst_dip_id'),
            min_snapshots: 0,
            max_snapshots: 0,
            snapshot_max_age: 0
          )

          pending 'complex repeated rollback + tree switching can strand old snapshots because metadata is not enough to derive safe rotation order'

          failed_chain_ids = []

          8.times do
            rotation = rotate_dataset(
              services,
              admin_user_id: admin_user_id,
              dip_id: @setup.fetch('dst_dip_id')
            )
            final_state = services.mysql_scalar(
              sql: "SELECT state FROM transaction_chains WHERE id = #{rotation.fetch('chain_id')}"
            ).to_i

            failed_chain_ids << rotation.fetch('chain_id') unless final_state == services.class::CHAIN_STATES[:done]
          end

          remaining = snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id')).map { |row| row.fetch('name') }
          branch_count_after = branch_rows_for_dip(services, @setup.fetch('dst_dip_id')).count
          tree_count_after = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          ).fetch('db').fetch('trees').count

          expect(failed_chain_ids).to eq([])
          expect(remaining.count).to be < count_before
          expect(branch_count_after).to be <= branch_count_before
          expect(tree_count_after).to be <= tree_count_before
        end
      end
    '';
  }
)
