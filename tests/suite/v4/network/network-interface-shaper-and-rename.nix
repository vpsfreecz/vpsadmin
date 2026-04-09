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
    name = "network-interface-shaper-and-rename";
    description = ''
      Update shaper limits and rename a routed interface while checking both
      the database row and the runtime interface listing.
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

      describe 'network interface shaper and rename', order: :defined do
        it 'updates the shaper and renames the routed interface' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'netif-rename',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'netif-rename',
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
          wait_for_netif_present(node, vps_id: vps.fetch('id'), name: 'eth1')

          shaper = update_netif(
            services,
            admin_user_id: admin_user_id,
            netif_id: created.fetch('netif_id'),
            attrs: { max_tx: 2048, max_rx: 4096 }
          )
          expect_chain_done(
            services,
            shaper,
            label: 'set shaper',
            expected_handles: [tx_types(services).fetch('netif_set_shaper')]
          )

          shaper_row = network_interface_row(services, created.fetch('netif_id'))
          expect(shaper_row.fetch('max_tx')).to eq(2048)
          expect(shaper_row.fetch('max_rx')).to eq(4096)

          renamed = update_netif(
            services,
            admin_user_id: admin_user_id,
            netif_id: created.fetch('netif_id'),
            attrs: { name: 'wan0' }
          )
          expect_chain_done(
            services,
            renamed,
            label: 'rename netif',
            expected_handles: [tx_types(services).fetch('netif_rename')]
          )

          renamed_row = network_interface_row(services, created.fetch('netif_id'))
          expect(renamed_row.fetch('name')).to eq('wan0')
          expect(renamed_row.fetch('max_tx')).to eq(2048)
          expect(renamed_row.fetch('max_rx')).to eq(4096)

          wait_for_netif_absent(node, vps_id: vps.fetch('id'), name: 'eth1')
          wait_for_netif_present(node, vps_id: vps.fetch('id'), name: 'wan0')
        end
      end
    '';
  }
)
