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
    name = "storage-branching-destroy";

    description = ''
      Build a repeated remote rollback topology, destroy the backup dataset
      directly through the transaction chain, and verify the snapshots and
      branch metadata are removed in dependency-safe order.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'destroying branched backup history', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-branch-destroy',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'destroys branched snapshots in dependency-safe order until the backup dataset is gone' do
          build_repeated_rollback_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            vps_id: @setup.fetch('vps_id'),
            label_prefix: 'destroy-topology'
          )

          response = destroy_backup_dataset(
            services,
            admin_user_id: admin_user_id,
            dip_id: @setup.fetch('dst_dip_id')
          )
          services.wait_for_chain_states(response.fetch('chain_id'), states: %i[done failed fatal resolved])

          final_state = services.mysql_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{response.fetch('chain_id')}"
          ).to_i
          tree_count = services.mysql_scalar(
            sql: "SELECT COUNT(*) FROM dataset_trees WHERE dataset_in_pool_id = #{@setup.fetch('dst_dip_id')}"
          ).to_i
          branch_count = services.mysql_scalar(
            sql: <<~SQL
              SELECT COUNT(*)
              FROM branches b
              INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
              WHERE t.dataset_in_pool_id = #{@setup.fetch('dst_dip_id')}
            SQL
          ).to_i
          sip_count = services.mysql_scalar(
            sql: "SELECT COUNT(*) FROM snapshot_in_pools WHERE dataset_in_pool_id = #{@setup.fetch('dst_dip_id')}"
          ).to_i
          entry_count = services.mysql_scalar(
            sql: <<~SQL
              SELECT COUNT(*)
              FROM snapshot_in_pool_in_branches e
              INNER JOIN snapshot_in_pools sip ON sip.id = e.snapshot_in_pool_id
              WHERE sip.dataset_in_pool_id = #{@setup.fetch('dst_dip_id')}
            SQL
          ).to_i

          expect(final_state).to eq(services.class::CHAIN_STATES[:done])
          expect(node2.zfs_exists?(@setup.fetch('backup_dataset_path'), type: 'filesystem', timeout: 30)).to be(false)
          expect(tree_count).to eq(0)
          expect(branch_count).to eq(0)
          expect(sip_count).to eq(0)
          expect(entry_count).to eq(0)
        end
      end
    '';
  }
)
