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
    name = "storage-dataset-destroy-after-rollback-history";

    description = ''
      Build a repeated remote rollback topology and verify that destroying the
      whole dataset removes both primary and backup storage metadata in a
      dependency-safe order.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'destroying a dataset after rollback history', order: :defined do
        it 'creates a standalone remote backup dataset' do
          @setup = create_remote_backup_dataset(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            dataset_name: 'storage-dataset-destroy',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'destroys the whole dataset after repeated rollback history' do
          build_repeated_rollback_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label_prefix: 'dataset-destroy'
          )

          response = destroy_dataset(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id')
          )
          wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )

          final_state = services.mysql_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{response.fetch('chain_id')}"
          ).to_i
          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          counts = dataset_record_counts(
            services,
            dataset_id: @setup.fetch('dataset_id')
          )

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), failure_details.inspect
          expect(node1.zfs_exists?(@setup.fetch('primary_dataset_path'), type: 'filesystem', timeout: 30)).to be(false)
          expect(node2.zfs_exists?(@setup.fetch('backup_dataset_path'), type: 'filesystem', timeout: 30)).to be(false)
          expect(counts).to eq(
            'datasets' => 0,
            'dataset_in_pools' => 0,
            'dataset_trees' => 0,
            'branches' => 0,
            'snapshot_in_pools' => 0,
            'snapshot_in_pool_in_branches' => 0
          )
          expect(failure_details).to eq([]), failure_details.inspect
        end
      end
    '';
  }
)
