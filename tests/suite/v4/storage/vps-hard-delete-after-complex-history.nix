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
    name = "storage-vps-hard-delete-after-complex-history";

    description = ''
      Hard-delete a VPS after complex remote rollback / tree-switch history,
      verify the primary storage is removed, backups are detached but preserved,
      and the remaining backup-only dataset can still be fully destroyed.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'VPS hard delete after complex history', order: :defined do
        it 'hard-deletes the VPS while keeping remaining backup metadata consistent' do
          setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-vps-hard-delete-complex',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

          build_complex_multi_tree_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            vps_id: setup.fetch('vps_id'),
            label_prefix: 'vps-hard-delete'
          )

          response = hard_delete_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: setup.fetch('vps_id')
          )

          final_state = services.mysql_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{response.fetch('chain_id')}"
          ).to_i
          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          dependency_failures = dependency_failure_details(services, response.fetch('chain_id'))
          vps_row = vps_unscoped_row(services, setup.fetch('vps_id'))
          head_counts = backup_head_counts(services, dataset_id: setup.fetch('dataset_id'))
          dataset_row = services.mysql_json_rows(sql: <<~SQL).first
            SELECT JSON_OBJECT('expiration_date', expiration_date)
            FROM datasets
            WHERE id = #{setup.fetch('dataset_id')}
            LIMIT 1
          SQL

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), failure_details.inspect
          expect(dependency_failures).to eq([]), failure_details.inspect
          expect(
            node1.zfs_exists?(
              setup.fetch('primary_dataset_path'),
              type: 'filesystem',
              timeout: 30
            )
          ).to be(false)
          expect(
            node2.zfs_exists?(
              setup.fetch('backup_dataset_path'),
              type: 'filesystem',
              timeout: 30
            )
          ).to be(true)
          expect(vps_row.fetch('object_state')).to eq('hard_delete')
          expect(vps_row.fetch('dataset_in_pool_id')).to be_nil
          expect(vps_row.fetch('user_namespace_map_id')).to be_nil
          expect(head_counts).to eq(
            'tree_heads' => 0,
            'branch_heads' => 0
          )
          expect(dataset_row.fetch('expiration_date')).not_to be_nil
          expect(dataset_row.fetch('expiration_date').to_s).not_to eq("")

          destroy = destroy_dataset(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id')
          )
          wait_for_chain_states_local(
            services,
            destroy.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          destroy_final_state = services.mysql_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{destroy.fetch('chain_id')}"
          ).to_i
          destroy_failures = chain_failure_details(services, destroy.fetch('chain_id'))
          counts = dataset_record_counts(services, dataset_id: setup.fetch('dataset_id'))

          expect(destroy_final_state).to eq(
            services.class::CHAIN_STATES[:done]
          ), destroy_failures.inspect
          expect(
            node2.zfs_exists?(
              setup.fetch('backup_dataset_path'),
              type: 'filesystem',
              timeout: 30
            )
          ).to be(false)
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
