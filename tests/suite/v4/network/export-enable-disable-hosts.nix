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
    name = "export-enable-disable-hosts";
    description = ''
      Toggle export runtime state, add and remove allowed hosts, and check the
      resulting exportfs state on a single-node cluster.
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

      describe 'export runtime updates', order: :defined do
        it 'enables, disables, and edits export hosts without losing runtime state' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'export-hosts',
            filesystem: primary_pool_fs,
            role: 'primary'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          dataset = create_top_level_dataset(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool.fetch('id'),
            dataset_name: 'export-hosts'
          )

          export_network = ensure_private_export_network_with_ips(
            services,
            admin_user_id: admin_user_id,
            dataset_id: dataset.fetch('dataset_id'),
            count: 2
          )
          host_ip = export_network.fetch('ip_addresses').last

          export = create_export(
            services,
            admin_user_id: admin_user_id,
            dataset_id: dataset.fetch('dataset_id'),
            enabled: false
          )
          create_handles = chain_transactions(services, export.fetch('chain_id')).map { |row| row.fetch('handle') }
          expect(create_handles).to include(tx_types(services).fetch('export_create'))
          expect(create_handles).not_to include(tx_types(services).fetch('export_enable'))
          expect(export_runtime_row(services, export.fetch('id')).fetch('enabled')).to eq(false)

          enabled = update_export(
            services,
            admin_user_id: admin_user_id,
            export_id: export.fetch('id'),
            attrs: { enabled: true, threads: 12 }
          )
          expect_chain_done(
            services,
            enabled,
            label: 'enable export',
            expected_handles: [
              tx_types(services).fetch('export_set'),
              tx_types(services).fetch('export_enable')
            ]
          )

          wait_for_export_present(node, export.fetch('id'), expected_path: export.fetch('path'))
          expect(export_runtime_row(services, export.fetch('id')).fetch('enabled')).to eq(true)

          added_host = add_export_host(
            services,
            admin_user_id: admin_user_id,
            export_id: export.fetch('id'),
            ip_address_id: host_ip.fetch('id')
          )
          add_handles = chain_transactions(services, added_host.fetch('chain_id')).map { |row| row.fetch('handle') }
          expect(add_handles).to include(tx_types(services).fetch('export_add_hosts'))
          expect(export_host_rows(services, export.fetch('id')).map { |row| row.fetch('id') }).to include(added_host.fetch('export_host_id'))
          wait_until_block_succeeds(name: "export host #{host_ip.fetch('addr')} present") do
            export_runtime_dump(node, export.fetch('id')).include?(host_ip.fetch('addr'))
          end

          disabled = update_export(
            services,
            admin_user_id: admin_user_id,
            export_id: export.fetch('id'),
            attrs: { enabled: false }
          )
          expect_chain_done(
            services,
            disabled,
            label: 'disable export',
            expected_handles: [tx_types(services).fetch('export_disable')]
          )
          expect(export_runtime_row(services, export.fetch('id')).fetch('enabled')).to eq(false)

          deleted_host = del_export_host(
            services,
            admin_user_id: admin_user_id,
            export_id: export.fetch('id'),
            export_host_id: added_host.fetch('export_host_id')
          )
          expect_chain_done(
            services,
            deleted_host,
            label: 'delete export host',
            expected_handles: [tx_types(services).fetch('export_del_hosts')]
          )
          expect(export_host_rows(services, export.fetch('id'))).to eq([])

          reenabled = update_export(
            services,
            admin_user_id: admin_user_id,
            export_id: export.fetch('id'),
            attrs: { enabled: true }
          )
          expect_chain_done(
            services,
            reenabled,
            label: 're-enable export',
            expected_handles: [tx_types(services).fetch('export_enable')]
          )

          wait_for_export_present(node, export.fetch('id'), expected_path: export.fetch('path'))
          expect(export_runtime_dump(node, export.fetch('id'))).not_to include(host_ip.fetch('addr'))
        end
      end
    '';
  }
)
