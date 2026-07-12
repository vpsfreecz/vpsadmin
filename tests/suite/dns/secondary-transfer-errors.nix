import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    dnsSeed = import ../../../api/db/seeds/test-dns-server-node.nix;
    dnsNode = dnsSeed.dnsNode;
    common = import ../tasks/common.nix {
      adminUserId = adminUser.id;
      node1Id = dnsNode.id;
      manageCluster = false;
    };
  in
  {
    name = "dns-secondary-transfer-errors";
    description = ''
      Record BIND secondary zone transfer failures from DNS-node journal logs,
      expose them through the API, and prune old transfer log history.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "network"
    ];

    machines = import ../../machines/dns-server-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      def emit_bind_log(node, message)
        printf_cmd = Shellwords.join(['printf', "%s\n", message])
        node.succeeds("#{printf_cmd} | ${pkgs.systemd}/bin/systemd-cat -t named")
      end

      def server_zone_transfer_state(services, server_zone_id)
        services.api_ruby_json(code: <<~RUBY)
          zone = DnsServerZone.find(#{Integer(server_zone_id)})
          logs = zone.dns_server_zone_transfer_logs.order(:event_at, :id)

          puts JSON.dump(
            id: zone.id,
            last_transfer_status: zone.last_transfer_status,
            last_transfer_reason_code: zone.last_transfer_reason_code,
            last_transfer_reason: zone.last_transfer_reason,
            last_transfer_primary_addr: zone.last_transfer_primary_addr,
            last_transfer_serial: zone.last_transfer_serial,
            last_transfer_log_id: zone.last_transfer_log_id,
            log_count: logs.count,
            reason_codes: logs.map(&:reason_code).compact,
            statuses: logs.map(&:status)
          )
        RUBY
      end

      def wait_for_transfer_state(services, server_zone_id:, status:, reason_code: nil, serial: nil)
        wait_until_block_succeeds(name: "DNS transfer state #{status} #{reason_code || serial}") do
          state = server_zone_transfer_state(services, server_zone_id)
          expect(state.fetch('last_transfer_status')).to eq(status)
          expect(state.fetch('last_transfer_reason_code')).to eq(reason_code) if reason_code
          expect(state.fetch('last_transfer_serial')).to eq(serial) if serial
          state
        end
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

      describe 'DNS secondary transfer errors', order: :defined do
        it 'records every normalized transfer failure and recovery' do
          dns_server = create_dns_server_runtime(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            name: 'ns1.transfer-errors.test'
          )

          zone = create_dns_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            name: 'secondary-errors.test.',
            source: 'external_source'
          )

          created_zone = create_dns_server_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_id: zone.fetch('id'),
            dns_server_id: dns_server.fetch('id'),
            zone_type: 'secondary_type'
          )
          expect_chain_done(
            services,
            created_zone,
            label: 'create external secondary zone',
            expected_handles: [
              tx_types(services).fetch('dns_server_zone_create'),
              tx_types(services).fetch('dns_server_reload')
            ]
          )

          server_zone_id = created_zone.fetch('id')
          zone_name = 'secondary-errors.test'
          failures = [
            ["zone #{zone_name}/IN: not loaded due to errors.", 'invalid_zone'],
            ["transfer of '#{zone_name}/IN' from 192.0.2.1#53: Transfer status: REFUSED", 'refused'],
            ["transfer of '#{zone_name}/IN' from 192.0.2.1#53: Transfer status: NOTAUTH", 'not_authoritative'],
            ["transfer of '#{zone_name}/IN' from 192.0.2.1#53: Transfer status: NXDOMAIN", 'not_found'],
            ["transfer of '#{zone_name}/IN' from 192.0.2.1#53: Transfer status: SERVFAIL", 'servfail'],
            ["zone #{zone_name}/IN: refresh: failure trying primary 192.0.2.1#53: timed out", 'timeout'],
            ["transfer of '#{zone_name}/IN' from 192.0.2.1#53: failed while receiving responses: connection refused", 'connection_failed'],
            ["transfer of '#{zone_name}/IN' from 192.0.2.1#53: Transfer status: TSIG verify failure", 'tsig_error'],
            ["transfer of '#{zone_name}/IN' from 192.0.2.1#53: Transfer status: unexpected EOF", 'unknown']
          ]

          failures.each do |message, reason_code|
            emit_bind_log(dns, message)
            wait_for_transfer_state(
              services,
              server_zone_id: server_zone_id,
              status: 'failed',
              reason_code: reason_code
            )
          end

          state = server_zone_transfer_state(services, server_zone_id)
          expect(state.fetch('reason_codes')).to include(*failures.map(&:last))

          emit_bind_log(
            dns,
            "zone #{zone_name}/IN: notify from 192.0.2.1#43627: zone is up to date"
          )
          state = wait_for_transfer_state(
            services,
            server_zone_id: server_zone_id,
            status: 'success'
          )
          expect(state.fetch('last_transfer_reason_code')).to be_nil
          expect(state.fetch('last_transfer_reason')).to be_nil
          expect(state.fetch('last_transfer_primary_addr')).to eq('192.0.2.1')
          expect(state.fetch('last_transfer_serial')).to be_nil

          emit_bind_log(
            dns,
            "transfer of '#{zone_name}/IN' from 192.0.2.1#53: Transfer completed: " \
            '1 messages, 5 records, 400 bytes, 0.001 secs (serial 2026050901)'
          )
          wait_for_transfer_state(
            services,
            server_zone_id: server_zone_id,
            status: 'success',
            serial: 2_026_050_901
          )
        end

        it 'prunes old transfer logs while keeping latest transfer fields' do
          server_zone_id = services.api_ruby_json(code: <<~RUBY).fetch('id')
            zone = DnsZone.find_by!(name: 'secondary-errors.test.')
            puts JSON.dump(id: zone.dns_server_zones.take!.id)
          RUBY

          services.api_ruby_json(code: <<~RUBY)
            server_zone = DnsServerZone.find(#{Integer(server_zone_id)})
            old_log = server_zone.dns_server_zone_transfer_logs.order(:id).last
            server_zone.dns_server_zone_transfer_logs.update_all(event_at: 2.years.ago)
            server_zone.update!(
              last_transfer_log: old_log,
              last_transfer_at: 2.years.ago
            )
            puts JSON.dump(status: true)
          RUBY

          run_api_rake_task(
            services,
            task: 'vpsadmin:dns:prune_transfer_logs',
            env: { 'DAYS' => '365' }
          )

          state = server_zone_transfer_state(services, server_zone_id)
          expect(state.fetch('log_count')).to eq(0)
          expect(state.fetch('last_transfer_status')).to eq('success')
          expect(state.fetch('last_transfer_serial')).to eq(2_026_050_901)
          expect(state.fetch('last_transfer_log_id')).to be_nil
        end
      end
    '';
  }
)
