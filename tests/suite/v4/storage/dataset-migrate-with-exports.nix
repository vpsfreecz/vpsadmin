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
    name = "storage-dataset-migrate-with-exports";

    description = ''
      Migrate an exported dataset to another primary pool, keeping the export
      attached to the destination dataset while removing it from the source
      node.
    '';

    tags = [
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'dataset migration with exports', order: :defined do
        it 'recreates the export on the destination node during cross-node migration' do
          setup = create_primary_dataset(
            services,
            primary_node: node1,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'dataset-migrate-export',
            primary_pool_fs: primary_pool_fs
          )
          dst_pool_fs = 'tank/export-dst'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'dataset-export-dst',
            filesystem: dst_pool_fs,
            role: 'primary'
          )

          wait_for_pool_online(services, dst_pool.fetch('id'))
          generate_migration_keys(services)
          export_network = ensure_private_export_network_with_ips(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            count: 2
          )

          export = create_export(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            enabled: true
          )
          add_export_host(
            services,
            admin_user_id: admin_user_id,
            export_id: export.fetch('id'),
            ip_address_id: export_network.fetch('ip_addresses').last.fetch('id')
          )

          wait_until_block_succeeds(name: 'source export visible') do
            node1.succeeds(
              "osctl-exportfs export ls #{Integer(export.fetch('id'))} | grep -F -- #{Shellwords.escape(export.fetch('path'))}",
              timeout: 30
            )
            true
          end

          response = dataset_migrate(
            services,
            dataset_id: setup.fetch('dataset_id'),
            pool_id: dst_pool.fetch('id'),
            send_mail: false
          )
          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          dst_info = dataset_in_pool_info(
            services,
            dataset_id: setup.fetch('dataset_id'),
            pool_id: dst_pool.fetch('id')
          )
          export_after = export_row(services, export.fetch('id'))

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), failure_details.inspect
          expect(dst_info).not_to be_nil
          expect(export_after.fetch('dataset_in_pool_id')).to eq(dst_info.fetch('dataset_in_pool_id'))
          expect(export_after.fetch('node_id')).to eq(node2_id)
          expect(export_after.fetch('enabled')).to be(true)

          wait_until_block_succeeds(name: 'destination export visible') do
            node2.succeeds(
              "osctl-exportfs export ls #{Integer(export_after.fetch('id'))} | grep -F -- #{Shellwords.escape(export_after.fetch('path'))}",
              timeout: 30
            )
            true
          end

          wait_until_block_succeeds(name: 'source export removed') do
            node1.fails(
              "osctl-exportfs export ls #{Integer(export_after.fetch('id'))} | grep -F -- #{Shellwords.escape(export_after.fetch('path'))}",
              timeout: 30
            )
            true
          end
        end
      end
    '';
  }
)
