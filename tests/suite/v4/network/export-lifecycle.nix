import ../../../make-test.nix (
  { ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      manageCluster = false;
    };
  in
  {
    name = "export-lifecycle";
    description = ''
      Create and destroy a primary-dataset export, verifying exportfs runtime
      state and cleanup of the export network interface and address.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "network"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'export lifecycle', order: :defined do
        it 'creates and destroys a dataset export end to end' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'export-lifecycle',
            filesystem: primary_pool_fs,
            role: 'primary'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          dataset = create_top_level_dataset(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool.fetch('id'),
            dataset_name: 'export-lifecycle'
          )

          ensure_private_export_network_with_ips(
            services,
            admin_user_id: admin_user_id,
            dataset_id: dataset.fetch('dataset_id'),
            count: 1
          )

          export = create_export(
            services,
            admin_user_id: admin_user_id,
            dataset_id: dataset.fetch('dataset_id'),
            enabled: true
          )
          runtime = export_runtime_row(services, export.fetch('id'))
          handles = chain_transactions(services, export.fetch('chain_id')).map { |row| row.fetch('handle') }

          expect(handles).to include(
            tx_types(services).fetch('export_create'),
            tx_types(services).fetch('export_enable')
          )
          expect(runtime).not_to be_nil
          wait_for_export_present(node, export.fetch('id'), expected_path: export.fetch('path'))

          destroyed = destroy_export(
            services,
            admin_user_id: admin_user_id,
            export_id: export.fetch('id')
          )
          expect_chain_done(
            services,
            destroyed,
            label: 'destroy export',
            expected_handles: [
              tx_types(services).fetch('export_disable'),
              tx_types(services).fetch('export_destroy')
            ]
          )

          wait_for_export_absent(node, export.fetch('id'), expected_path: export.fetch('path'))
          expect(export_runtime_row(services, export.fetch('id'))).to be_nil
          expect(network_interface_row(services, runtime.fetch('network_interface_id'))).to be_nil
          expect(ip_address_row(services, runtime.fetch('ip_address_id')).fetch('network_interface_id')).to be_nil
        end
      end
    '';
  }
)
