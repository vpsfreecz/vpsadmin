import ../../../make-test.nix (
  { ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    dnsSeed = import ../../../../api/db/seeds/test-dns-server-node.nix;
    dnsNode = dnsSeed.dnsNode;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = dnsNode.id;
      manageCluster = false;
    };
  in
  {
    name = "dns-zone-transfer-config";
    description = ''
      Add and remove a DNS zone transfer peer, verifying generated BIND
      configuration and reload behavior.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "network"
    ];

    machines = import ../../../machines/v4/dns-server-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        [services, dns].each(&:start)
        services.wait_for_vpsadmin_api
        services.wait_for_service('vpsadmin-rabbitmq-setup.service')
        services.wait_for_service('vpsadmin-supervisor.service')
        dns.wait_for_service('bind.service')
        restart_nixos_nodectld(dns)
        wait_for_nixos_nodectld(dns)
        wait_for_dns_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'dns zone transfer config', order: :defined do
        it 'adds and removes transfer peers from generated config' do
          dns_server = create_dns_server_runtime(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            name: 'ns1.dns.test'
          )

          zone = create_dns_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            name: 'transfer.test.',
            source: 'internal_source'
          )

          created_zone = create_dns_server_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_id: zone.fetch('id'),
            dns_server_id: dns_server.fetch('id'),
            zone_type: 'primary_type'
          )
          expect_chain_done(
            services,
            created_zone,
            label: 'create transfer zone',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_create'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )

          peer = create_dns_transfer_host_ip_runtime(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            addr: '203.0.113.250'
          )

          transfer = create_dns_zone_transfer_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_id: zone.fetch('id'),
            host_ip_id: peer.fetch('host_ip_id'),
            peer_type: 'secondary_type'
          )
          expect_chain_done(
            services,
            transfer,
            label: 'create zone transfer',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_add_servers'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )
          wait_until_block_succeeds(name: 'named config contains transfer peer') do
            text = named_config_text(dns)
            expect(text).to include('zone "transfer.test."')
            expect(text).to include('allow-transfer { 203.0.113.250; };')
            true
          end

          destroyed = destroy_dns_zone_transfer_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_transfer_id: transfer.fetch('id')
          )
          expect_chain_done(
            services,
            destroyed,
            label: 'destroy zone transfer',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_remove_servers'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )
          wait_until_block_succeeds(name: 'named config no longer contains transfer peer') do
            text = named_config_text(dns)
            expect(text).to include('zone "transfer.test."')
            expect(text).not_to include('203.0.113.250')
            true
          end
        end
      end
    '';
  }
)
