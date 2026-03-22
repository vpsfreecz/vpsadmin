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
    name = "storage-dataset-destroy-complex-history";

    description = ''
      Verify whole-dataset destroy across repeated rollback and tree-switching
      history removes both local and backup state in a dependency-safe order.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'destroying a dataset across complex history', order: :defined do
        it 'creates a standalone remote backup dataset' do
          @setup = create_remote_backup_dataset(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            dataset_name: 'storage-dataset-destroy-complex',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'destroys the dataset across tree switches without dependency-order failures' do
          build_complex_multi_tree_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label_prefix: 'dataset-destroy-complex'
          )

          report_before = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          )
          diagnostic = delete_order_diagnostic(report_before)

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
          unexpected_failures = failure_details.reject { |detail| dependency_failure?(detail) }
          counts = dataset_record_counts(
            services,
            dataset_id: @setup.fetch('dataset_id')
          )

          expect(diagnostic.fetch('db_but_not_zfs')).to eq([]), diagnostic.inspect
          expect(unexpected_failures).to eq([]), failure_details.inspect
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
        end
      end
    '';
  }
)
