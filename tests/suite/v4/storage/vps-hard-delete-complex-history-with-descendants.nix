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
    name = "storage-vps-hard-delete-complex-history-with-descendants";

    description = ''
      Hard-delete a VPS after complex history with primary descendant datasets,
      verify the whole primary subtree is removed, backup metadata is detached,
      and the remaining backup-only root dataset can still be fully destroyed.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'VPS hard delete after complex history with descendants',
               order: :defined do
        it 'removes the primary subtree while preserving detached backups until later destroy' do
          setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-vps-hard-delete-desc',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: setup.fetch('dataset_id'),
            name: 'var',
            pool_fs: primary_pool_fs
          )
          middle = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: child.fetch('dataset_id'),
            name: 'lib',
            pool_fs: primary_pool_fs
          )
          grandchild = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: middle.fetch('dataset_id'),
            name: 'mysql',
            pool_fs: primary_pool_fs
          )

          [child, middle, grandchild].each_with_index do |descendant, idx|
            mountpoint = node1.zfs_get(
              fs: descendant.fetch('dataset_path'),
              property: 'mountpoint',
              timeout: 30
            ).last.strip

            file_path = File.join(mountpoint, 'spec-data', "file-#{idx}")
            node1.succeeds(
              "mkdir -p #{Shellwords.escape(File.join(mountpoint, 'spec-data'))} && " \
              "echo #{idx} > #{Shellwords.escape(file_path)}",
              timeout: 60
            )
          end

          build_complex_multi_tree_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            vps_id: setup.fetch('vps_id'),
            label_prefix: 'vps-hard-delete-desc'
          )

          subtree_ids = dataset_subtree_ids(services, setup.fetch('dataset_id'))

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
          remaining_datasets = services.mysql_scalar(sql: <<~SQL).to_i
            SELECT COUNT(*)
            FROM datasets
            WHERE id IN (#{subtree_ids.join(',')})
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
          expect(node1.zfs_exists?(child.fetch('dataset_path'), type: 'filesystem', timeout: 30)).to be(false)
          expect(node1.zfs_exists?(middle.fetch('dataset_path'), type: 'filesystem', timeout: 30)).to be(false)
          expect(node1.zfs_exists?(grandchild.fetch('dataset_path'), type: 'filesystem', timeout: 30)).to be(false)
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
          expect(remaining_datasets).to eq(subtree_ids.count)

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
          remaining_after_destroy = services.mysql_scalar(sql: <<~SQL).to_i
            SELECT COUNT(*)
            FROM datasets
            WHERE id IN (#{subtree_ids.join(',')})
          SQL

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
          expect(remaining_after_destroy).to eq(0)
        end
      end
    '';
  }
)
