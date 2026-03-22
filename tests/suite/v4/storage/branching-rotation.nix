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
    name = "storage-branching-rotation";

    description = ''
      Build a repeated remote rollback topology, trigger aggressive backup
      rotation, and verify old backup snapshots are deleted without touching
      parents that still have live dependents.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      def rotate_dataset(services, admin_user_id:, dip_id:)
        response = services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          dip = DatasetInPool.find(#{dip_id})
          chain, = TransactionChains::Dataset::Rotate.fire(dip)

          puts JSON.dump(chain_id: chain.id)
        RUBY

        wait_for_chain_states_local(
          services,
          response.fetch('chain_id'),
          %i[done failed fatal resolved]
        )
        response
      end

      describe 'rotation on branched backup history', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-branch-rotation',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'eventually deletes unreferenced branched snapshots without deleting live parents' do
          topology = build_repeated_rollback_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            vps_id: @setup.fetch('vps_id'),
            label_prefix: 'rotate-topology'
          )

          count_before = snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id')).count

          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'rotate-topology-s9'
          )
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'rotate-topology-s10'
          )

          set_snapshot_retention(
            services,
            dip_id: @setup.fetch('dst_dip_id'),
            min_snapshots: 0,
            max_snapshots: 0,
            snapshot_max_age: 0
          )

          rotation = rotate_dataset(
            services,
            admin_user_id: admin_user_id,
            dip_id: @setup.fetch('dst_dip_id')
          )
          final_state = services.mysql_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{rotation.fetch('chain_id')}"
          ).to_i
          backup_names = snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id')).map { |row| row.fetch('name') }
          entries = branch_entries_for_dip(services, @setup.fetch('dst_dip_id'))

          expect(final_state).to eq(services.class::CHAIN_STATES[:done])
          expect(backup_names.count).to be < (count_before + 2)
          expect(backup_names).not_to include(topology.fetch('snapshots').fetch('s1').fetch('name'))

          entries.select { |row| row.fetch('reference_count') > 0 }.each do |entry|
            expect(backup_names).to include(entry.fetch('snapshot_name'))
          end
        end
      end
    '';
  }
)
