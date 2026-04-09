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
    name = "network-interface-routes-and-host-ips";
    description = ''
      Route an extra IPv4 address to a routed interface, add and remove the
      host address, and verify cluster-resource accounting changes.
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

      describe 'network routes and host addresses', order: :defined do
        it 'adds and removes routes and host addresses on a routed interface' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'netif-routes',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'netif-routes',
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

          network = create_private_vps_network_with_ips(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            count: 1
          )
          ip = network.fetch('ip_addresses').first
          cidr = "#{ip.fetch('addr')}/32"
          before_uses = environment_user_resource_uses(
            services,
            user_id: admin_user_id,
            environment_id: network.fetch('environment_id')
          ).each_with_object(Hash.new(0)) do |row, acc|
            acc[row.fetch('resource')] = row.fetch('value').to_i
          end

          added_route = add_route_to_netif(
            services,
            admin_user_id: admin_user_id,
            netif_id: created.fetch('netif_id'),
            ip_id: ip.fetch('id')
          )
          expect_chain_done(
            services,
            added_route,
            label: 'add route',
            expected_handles: [tx_types(services).fetch('netif_add_route')]
          )

          route_row = ip_address_row(services, ip.fetch('id'))
          after_uses = environment_user_resource_uses(
            services,
            user_id: admin_user_id,
            environment_id: network.fetch('environment_id')
          ).each_with_object(Hash.new(0)) do |row, acc|
            acc[row.fetch('resource')] = row.fetch('value').to_i
          end

          expect(route_row.fetch('network_interface_id')).to eq(created.fetch('netif_id'))
          expect(route_row.fetch('route_via_id')).to be_nil
          expect(route_row.fetch('order')).to eq(0)
          expect(after_uses.fetch('ipv4_private', 0)).to eq(
            before_uses.fetch('ipv4_private', 0) + 1
          )
          wait_for_route_present(node, vps_id: vps.fetch('id'), name: 'eth1', cidr: cidr)

          added_host_ip = add_host_ip_to_netif(
            services,
            admin_user_id: admin_user_id,
            netif_id: created.fetch('netif_id'),
            host_ip_id: ip.fetch('host_ip_id')
          )
          expect_chain_done(
            services,
            added_host_ip,
            label: 'add host ip',
            expected_handles: [tx_types(services).fetch('netif_add_host_ip')]
          )

          host_row = host_ip_address_row(services, ip.fetch('host_ip_id'))
          expect(host_row.fetch('order')).to eq(0)
          wait_for_host_ip_present(node, vps_id: vps.fetch('id'), name: 'eth1', cidr: cidr)

          removed_host_ip = del_host_ip_from_netif(
            services,
            admin_user_id: admin_user_id,
            netif_id: created.fetch('netif_id'),
            host_ip_id: ip.fetch('host_ip_id')
          )
          expect_chain_done(
            services,
            removed_host_ip,
            label: 'del host ip',
            expected_handles: [tx_types(services).fetch('netif_del_host_ip')]
          )

          expect(host_ip_address_row(services, ip.fetch('host_ip_id')).fetch('order')).to be_nil
          wait_for_host_ip_absent(node, vps_id: vps.fetch('id'), name: 'eth1', cidr: cidr)

          removed_route = del_route_from_netif(
            services,
            admin_user_id: admin_user_id,
            netif_id: created.fetch('netif_id'),
            ip_id: ip.fetch('id')
          )
          expect_chain_done(
            services,
            removed_route,
            label: 'del route',
            expected_handles: [tx_types(services).fetch('netif_del_route')]
          )

          final_row = ip_address_row(services, ip.fetch('id'))
          final_uses = environment_user_resource_uses(
            services,
            user_id: admin_user_id,
            environment_id: network.fetch('environment_id')
          ).each_with_object(Hash.new(0)) do |row, acc|
            acc[row.fetch('resource')] = row.fetch('value').to_i
          end

          expect(final_row.fetch('network_interface_id')).to be_nil
          expect(final_row.fetch('route_via_id')).to be_nil
          expect(final_row.fetch('order')).to be_nil
          expect(final_uses.fetch('ipv4_private', 0)).to eq(
            before_uses.fetch('ipv4_private', 0)
          )
          wait_for_route_absent(node, vps_id: vps.fetch('id'), name: 'eth1', cidr: cidr)
        end
      end
    '';
  }
)
