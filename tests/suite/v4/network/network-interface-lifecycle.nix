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
    name = "network-interface-lifecycle";
    description = ''
      Create, toggle, and destroy an extra routed interface on a single-node
      cluster while checking database and node runtime state.
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

      describe 'network interface lifecycle', order: :defined do
        it 'creates, disables, re-enables, and destroys a routed interface' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'netif-lifecycle',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'netif-lifecycle',
            start: false
          )

          created = create_veth_routed_netif(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            name: 'eth1'
          )
          expect_chain_done(
            services,
            created,
            label: 'create netif',
            expected_handles: [tx_types(services).fetch('netif_create_veth_routed')]
          )
          start_vps(services, vps.fetch('id'))

          row = network_interface_row(services, created.fetch('netif_id'))
          expect(row).not_to be_nil
          expect(row.fetch('name')).to eq('eth1')
          wait_for_netif_present(node, vps_id: vps.fetch('id'), name: 'eth1')

          disabled = update_netif(
            services,
            admin_user_id: admin_user_id,
            netif_id: created.fetch('netif_id'),
            attrs: { enable: false }
          )
          expect_chain_done(
            services,
            disabled,
            label: 'disable netif',
            expected_handles: [tx_types(services).fetch('netif_disable')]
          )
          expect(network_interface_row(services, created.fetch('netif_id')).fetch('enable')).to eq(false)

          enabled = update_netif(
            services,
            admin_user_id: admin_user_id,
            netif_id: created.fetch('netif_id'),
            attrs: { enable: true }
          )
          expect_chain_done(
            services,
            enabled,
            label: 'enable netif',
            expected_handles: [tx_types(services).fetch('netif_enable')]
          )
          expect(network_interface_row(services, created.fetch('netif_id')).fetch('enable')).to eq(true)

          stop_vps(services, vps.fetch('id'), node_id: node1_id)
          destroyed = destroy_netif(
            services,
            admin_user_id: admin_user_id,
            netif_id: created.fetch('netif_id')
          )
          expect_chain_done(
            services,
            destroyed,
            label: 'destroy netif',
            expected_handles: [tx_types(services).fetch('netif_remove_veth_routed')]
          )

          expect(network_interface_row(services, created.fetch('netif_id'))).to be_nil
          start_vps(services, vps.fetch('id'))
          wait_for_netif_absent(node, vps_id: vps.fetch('id'), name: 'eth1')
        end
      end
    '';
  }
)
