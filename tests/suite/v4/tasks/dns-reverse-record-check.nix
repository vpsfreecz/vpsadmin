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
    name = "tasks-dns-reverse-record-check";

    description = ''
      Check reverse DNS records against the live test DNS server, then verify
      the task fails when the database expectation diverges from DNS.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "tasks"
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

      describe 'DNS reverse-record task', order: :defined do
        it 'succeeds for matching live PTR answers and fails after DB-only drift' do
          dns_server = create_dns_server_runtime(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            name: 'ns-reverse.dns.test'
          )
          zone = create_reverse_dns_zone_runtime(
            services,
            name: '113.0.203.in-addr.arpa.',
            network_address: '203.0.113.0',
            network_prefix: 24
          )
          server_zone = create_dns_server_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_id: zone.fetch('id'),
            dns_server_id: dns_server.fetch('id'),
            zone_type: 'primary_type'
          )
          expect_chain_done(
            services,
            server_zone,
            label: 'create reverse dns server zone',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_create'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )

          host = create_dns_transfer_host_ip_runtime(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            addr: '203.0.113.25'
          )
          record = create_dns_record_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_id: zone.fetch('id'),
            attrs: {
              name: '25',
              record_type: 'PTR',
              content: 'host.example.test.',
              enabled: true
            }
          )
          expect_chain_done(
            services,
            record,
            label: 'create reverse PTR',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_create_records'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )
          set_host_ip_reverse_record(
            services,
            host_ip_id: host.fetch('host_ip_id'),
            dns_record_id: record.fetch('id')
          )

          zone_file = dns_zone_file_path(
            name: '113.0.203.in-addr.arpa.',
            source: 'internal_source',
            type: 'primary_type'
          )
          wait_for_dns_text(dns, path: zone_file, includes: ['25', 'PTR', 'host.example.test.'])

          run_api_rake_task(
            services,
            task: 'vpsadmin:dns:check_reverse_records',
            env: { SERVERS: dns_server.fetch('name') },
            timeout: 300
          )

          update_dns_record_content_without_runtime(
            services,
            dns_record_id: record.fetch('id'),
            content: 'other.example.test.'
          )
          run_api_rake_task(
            services,
            task: 'vpsadmin:dns:check_reverse_records',
            env: { SERVERS: dns_server.fetch('name') },
            expect_success: false,
            timeout: 300
          )
        end
      end
    '';
  }
)
