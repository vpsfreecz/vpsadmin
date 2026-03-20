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
    name = "storage-history-divergence-new-tree-pending";

    description = ''
      Create remote backup history, reinstall the VPS to reset primary snapshot
      history, take a new snapshot, and keep the desired “new tree instead of
      silent warning/no-op” behavior as a pending bug contract.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'history divergence after reinstall', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-history-divergence',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'creates a new backup tree instead of silently warning and returning' do
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'divergence-s1'
          )
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'divergence-s2'
          )

          reinstall = reinstall_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: @setup.fetch('vps_id')
          )
          services.wait_for_chain_state(reinstall.fetch('chain_id'), state: :done)

          wait_until_block_succeeds(name: 'local snapshots removed after reinstall') do
            snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).empty?
          end

          @snap3 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'divergence-s3'
          )

          pending 'history divergence should create a new tree or fail explicitly instead of warning and returning'

          response = fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id')
          )

          services.wait_for_tree_count(@setup.fetch('dst_dip_id'), count: 2)
          expect(head_tree_row(services, @setup.fetch('dst_dip_id')).fetch('tree_index')).to eq(1)
          expect(response.fetch('chain_id')).to be_present
        end
      end
    '';
  }
)
