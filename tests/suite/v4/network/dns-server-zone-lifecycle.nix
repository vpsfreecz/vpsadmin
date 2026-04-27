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
    name = "dns-server-zone-lifecycle";
    description = ''
      Create, update, and destroy an internal DNS server zone through the
      real nodectld/BIND runtime path.
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

      describe 'dns server zone lifecycle', order: :defined do
        it 'creates, updates, and destroys runtime zone state' do
          dns_server = create_dns_server_runtime(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            name: 'ns1.dns.test'
          )

          zone = create_dns_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            name: 'example.test.',
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
            label: 'create dns server zone',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_create'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )

          zone_file = dns_zone_file_path(
            name: 'example.test.',
            source: 'internal_source',
            type: 'primary_type'
          )
          zone_db = dns_zone_db_path(
            name: 'example.test.',
            source: 'internal_source',
            type: 'primary_type'
          )

          wait_for_dns_text(dns, path: zone_db, includes: ['"name": "example.test."'])
          wait_for_dns_text(dns, path: zone_file, includes: [
            '$ORIGIN example.test.',
            '$TTL 3600',
            'SOA ns1.dns.test.',
            'NS ns1.dns.test.'
          ])
          wait_until_block_succeeds(name: 'named config contains example.test') do
            expect(named_config_text(dns)).to include('zone "example.test."')
            true
          end

          record = create_dns_record_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_id: zone.fetch('id'),
            attrs: {
              name: 'www',
              record_type: 'A',
              content: '192.0.2.44',
              ttl: 600,
              enabled: true
            }
          )
          expect_chain_done(
            services,
            record,
            label: 'create dns record',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_create_records'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )
          wait_for_dns_text(dns, path: zone_file, includes: ['www', '600', '192.0.2.44'])

          updated_record = update_dns_record_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_record_id: record.fetch('id'),
            attrs: {
              content: '192.0.2.45',
              ttl: 1200
            }
          )
          expect_chain_done(
            services,
            updated_record,
            label: 'update dns record',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_update_records'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )
          wait_until_block_succeeds(name: 'zone file contains updated record') do
            _, text = dns.succeeds("cat #{Shellwords.escape(zone_file)}")
            expect(text).to include('192.0.2.45')
            expect(text).to include('1200')
            expect(text).not_to include('192.0.2.44')
            true
          end

          updated_zone = update_dns_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_id: zone.fetch('id'),
            attrs: {
              default_ttl: 7200,
              email: 'hostmaster@example.test'
            }
          )
          expect_chain_done(
            services,
            updated_zone,
            label: 'update dns zone',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_update'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )
          wait_for_dns_text(dns, path: zone_file, includes: [
            '$TTL 7200',
            'hostmaster.example.test.'
          ])

          destroyed_record = destroy_dns_record_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_record_id: record.fetch('id')
          )
          expect_chain_done(
            services,
            destroyed_record,
            label: 'destroy dns record',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_delete_records'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )
          wait_until_block_succeeds(name: 'zone file no longer contains record') do
            _, text = dns.succeeds("cat #{Shellwords.escape(zone_file)}")
            expect(text).not_to include('192.0.2.45')
            true
          end

          destroyed_zone = destroy_dns_server_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_server_zone_id: created_zone.fetch('id')
          )
          expect_chain_done(
            services,
            destroyed_zone,
            label: 'destroy dns server zone',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_destroy'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )
          wait_for_dns_path_absent(dns, path: zone_file)
          wait_for_dns_path_absent(dns, path: zone_db)
          wait_until_block_succeeds(name: 'named config no longer contains example.test') do
            expect(named_config_text(dns)).not_to include('zone "example.test."')
            true
          end
        end
      end
    '';
  }
)
