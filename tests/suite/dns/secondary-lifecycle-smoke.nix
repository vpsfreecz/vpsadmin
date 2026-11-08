import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    dnsNode = (import ../../../api/db/seeds/test-dns-server-node.nix).dnsNode;
    nodeSeed = (import ../../../api/db/seeds/test-1-node.nix).nodes.node;
    baseMachines = import ../../machines/dns-server-node.nix args;
    cluster = import ../../machines/cluster/1-node.nix args;
    common = import ../network/common.nix {
      adminUserId = seed.adminUser.id;
      node1Id = nodeSeed.id;
      manageCluster = false;
    };
    primaryAddr = "192.168.10.50";
    aliasAddr = "192.168.10.32";
    zoneName = "secondary-lifecycle.test.";
    keyName = "lifecycle-smoke.test";
    # Disposable fixture key, shared only by the two test BIND instances.
    keySecret = "bGlmZWN5Y2xlLXNtb2tlLXRlc3Qta2V5";
    primaryZone = pkgs.writeText "secondary-lifecycle.zone" ''
      $ORIGIN ${zoneName}
      $TTL 60
      @ IN SOA ns.${zoneName} hostmaster.${zoneName} 2026110801 3600 60 604800 60
      @ IN NS ns.${zoneName}
      ns IN A ${primaryAddr}
      www IN A 192.0.2.80
    '';
    gateModule =
      { pkgs, ... }:
      let
        gateScript = pkgs.writeText "dns-lifecycle-probe-gate.rb" ''
          require 'json'
          require 'open3'

          payload = $stdin.read
          job = JSON.parse(payload)
          # No fabricated worker result or persistent scheduler state. The process
          # title lets the driver observe a real forced AXFR waiting at the gate.
          if job.fetch('force_axfr') && File.exist?('/run/dns-smoke-block-axfr')
            $0 = 'dns-smoke-blocked-axfr'
            sleep 0.1 while File.exist?('/run/dns-smoke-block-axfr')
          end
          stdout, stderr, status = Open3.capture3(
            '${pkgs.nodectld}/bin/vpsadmin-dns-transfer-probe', stdin_data: payload
          )
          $stdout.write(stdout)
          $stderr.write(stderr)
          exit(status.exitstatus)
        '';
        gateWorker = pkgs.writeShellScriptBin "dns-lifecycle-probe-gate" ''
          exec ${pkgs.ruby}/bin/ruby ${gateScript}
        '';
      in
      {
        vpsadmin.nodectld.settings.dns_server.transfer_probe_worker_command =
          pkgs.lib.mkForce "${gateWorker}/bin/dns-lifecycle-probe-gate";
      };
  in
  {
    name = "dns-secondary-lifecycle-smoke";
    description = ''
      Verify DNS configuration rollback, retained AXFR recovery and evidence
      aging, then owned route detach and disown against real node daemons.
    '';
    tags = [
      "ci"
      "vpsadmin"
      "network"
    ];

    # Native tests share one machine set. Only the last example boots node or
    # provisions a pool/VPS; the original transfer-errors suite stays separate.
    machines = baseMachines // {
      inherit (cluster) node;
      services = baseMachines.services // {
        config = {
          imports = [ baseMachines.services.config ];
          vpsadmin.test = {
            seedFiles = pkgs.lib.mkForce [
              "test.nix"
              "test-dns-server-node.nix"
              "test-1-node.nix"
            ];
            socketPeers.${nodeSeed.name} = nodeSeed.ipAddr;
            rabbitmqNodeUsers = [ nodeSeed.domain ];
          };
        };
      };
      dns = baseMachines.dns // {
        config = {
          imports = [
            baseMachines.dns.config
            gateModule
          ];
          vpsadmin.nodectld.settings.dns_server = {
            status_interval = 2;
            transfer_probe_interval = 5;
            transfer_probe_failure_interval = 3;
            transfer_probe_timeout = 3;
            transfer_probe_axfr_timeout = 10;
          };
        };
      };
      primary = {
        spin = "nixos";
        networks = [ { type = "socket"; } ];
        config = {
          networking = {
            hostName = "lifecycle-primary";
            firewall.allowedTCPPorts = [ 53 ];
            firewall.allowedUDPPorts = [ 53 ];
            interfaces.eth0 = {
              useDHCP = false;
              ipv4.addresses = [
                {
                  address = primaryAddr;
                  prefixLength = 24;
                }
              ];
            };
          };
          virtualisation = {
            memorySize = 768;
            cores = 1;
          };
          systemd.tmpfiles.rules = [ "d /var/named 0755 named named -" ];
          services.bind = {
            enable = true;
            package = pkgs.bind;
            directory = "/var/named";
            ipv4Only = true;
            listenOn = [ primaryAddr ];
            listenOnIpv6 = [ ];
            forwarders = [ ];
            cacheNetworks = [ ];
            configFile = pkgs.writeText "lifecycle-primary.conf" ''
              options {
                directory "/var/named";
                pid-file "/run/named/named.pid";
                session-keyfile "/run/named/session.key";
                listen-on port 53 { ${primaryAddr}; };
                listen-on-v6 { none; };
                allow-query { any; };
                recursion no;
                dnssec-validation no;
              };
              key "${keyName}" { algorithm hmac-sha256; secret "${keySecret}"; };
              acl secondary-sources { ${dnsNode.ipAddr}; ${aliasAddr}; };
              acl signed-secondary {
                !{ !secondary-sources; any; };
                key "${keyName}";
              };
              zone "${zoneName}" {
                type primary;
                file "${primaryZone}";
                allow-transfer { signed-secondary; };
                notify no;
              };
            '';
          };
        };
      };
    };

    testScript = common + ''
      configure_examples { |config| config.default_order = :defined }

      # Each api_ruby_json call starts a fresh process. Unlocking the HTTP API
      # workers does not unlock this process's transaction signer.
      alias dns_smoke_api_session_prelude api_session_prelude
      def api_session_prelude(admin_user_id)
        dns_smoke_api_session_prelude(admin_user_id) + <<~RUBY
          VpsAdmin::API::TransactionSigner.unlock('test')
        RUBY
      end

      DNS_ID = ${toString dnsNode.id}
      DNS_ADDR = '${dnsNode.ipAddr}'
      ALIAS_ADDR = '${aliasAddr}'
      PRIMARY_ADDR = '${primaryAddr}'
      ZONE_NAME = '${zoneName}'
      KEY_NAME = '${keyName}'
      LATCH_FILE = '/var/lib/nodectld/dns-transfer-probe.json'

      def smoke_ids
        @smoke_ids
      end

      def smoke_snapshot
        services.api_ruby_json(code: <<~RUBY)
          zone = DnsZone.find(#{Integer(smoke_ids.fetch('zone_id'))})
          server_zone = DnsServerZone.find(#{Integer(smoke_ids.fetch('server_zone_id'))})
          transfer = DnsZoneTransfer.find(#{Integer(smoke_ids.fetch('transfer_id'))})
          state = DnsServerZonePrimaryTransferState.find_by(
            dns_server_zone: server_zone, dns_zone_transfer: transfer
          )
          puts JSON.dump(
            generation: zone.primary_transfer_generation,
            tracking: zone.primary_transfer_tracking_started_at&.to_i,
            source: server_zone.dns_server.ipv4_addr,
            enabled: zone.enabled,
            state: state && {
              status: state.status, reason_code: state.reason_code,
              attempt_kind: state.last_attempt_kind, event_key: state.last_event_key,
              generation: state.configuration_generation,
              evidence_current: state.evidence_current,
              reason_observed_at: state.reason_observed_at&.to_f,
              last_attempt_at: state.last_attempt_at.to_f
            },
            aggregate: transfer.transfer_check_status,
            pending: transfer.transfer_check_pending_count,
            recovered: zone.primary_transfer_failure_resolution
          )
        RUBY
      end

      def assert_node_metadata(snapshot = smoke_snapshot)
        _, output = dns.succeeds("cat #{Shellwords.escape(dns_zone_db_path(name: ZONE_NAME))}")
        persisted = JSON.parse(output)
        expect(persisted.fetch('id')).to eq(smoke_ids.fetch('server_zone_id'))
        expect(persisted.fetch('primary_transfer_generation')).to eq(snapshot.fetch('generation'))
        expect(persisted.fetch('primary_transfer_tracking_started_at')).to eq(snapshot.fetch('tracking'))
        expect(persisted.fetch('probe_source_addrs').fetch('ipv4')).to eq(snapshot.fetch('source'))
        expect(persisted.fetch('enabled')).to eq(snapshot.fetch('enabled'))
        snapshot
      end

      def wait_for_smoke_probe(status:, kind: nil, after_key: nil, reason: nil)
        wait_until_block_succeeds(name: "real lifecycle probe #{status}/#{kind}") do
          snapshot = smoke_snapshot
          state = snapshot.fetch('state')
          expect(state).not_to be_nil
          expect(state.fetch('status')).to eq(status)
          expect(state.fetch('attempt_kind')).to match(/\A(?:ixfr|axfr)_probe\z/)
          expect(state.fetch('attempt_kind')).to eq(kind) if kind
          expect(state.fetch('event_key')).not_to eq(after_key) if after_key
          expect(state.fetch('reason_code')).to eq(reason) if reason
          expect(state.fetch('generation')).to eq(snapshot.fetch('generation'))
          expect(state.fetch('evidence_current')).to be(true)
          assert_node_metadata(snapshot)
        end
      end

      def update_smoke_source(addr, rollback: false)
        response = services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}
          server = DnsServer.find(#{Integer(smoke_ids.fetch('server_id'))})
          if #{rollback}
            class SmokeUnsupported < Transactions::Utils::NoOp
              t_name :smoke_unsupported
              t_type 990_991
              def self.label = 'Deliberate smoke rollback'
            end
            class SmokeSourceRollback < TransactionChain
              label 'DNS source rollback smoke'
              def link_chain(server, attrs)
                # Supervisor loads only the persisted ordinary base class.
                self.type = ::TransactionChain.sti_name
                use_chain(TransactionChains::DnsServer::Update, args: [server, attrs])
                append_t(Transactions::Utils::NoOp, args: server.node_id, kwargs: { sleep: 10 })
                append_t(SmokeUnsupported, args: server.node_id)
              end
            end
            chain, = SmokeSourceRollback.fire(server, ipv4_addr: #{addr.inspect})
            stored = TransactionChain.find(chain.id)
            failure = stored.transactions.find_by!(handle: 990_991)
            raise 'ephemeral STI type persisted' unless stored.type == TransactionChain.sti_name
            raise 'unsigned failure transaction' if failure.signature.blank?
            raise 'unsigned domain transaction' if stored.transactions.where(signature: nil).exists?
            raise 'failure is irreversible' unless failure.is_reversible?
            raise 'signed handle mismatch' unless JSON.parse(failure.input).fetch('handle') == failure.handle
          else
            chain, = TransactionChains::DnsServer::Update.fire(server, ipv4_addr: #{addr.inspect})
          end
          puts JSON.dump(chain_id: chain.id)
        RUBY
        if rollback
          wait_until_block_succeeds(name: 'prepared source reached the real node before rollback') do
            prepared = assert_node_metadata
            expect(prepared.fetch('source')).to eq(addr)
            true
          end
          terminal = wait_for_chain_states_local(services, response.fetch('chain_id'), %i[done failed fatal])
          expect(terminal).to eq(STORAGE_CHAIN_STATES.fetch(:failed))
          failure = wait_for_chain_failure_detail(services, response.fetch('chain_id'), handle: 990_991)
          expect(failure.to_json).to include('Unsupported command')
          wait_for_chain_locks_released(services, response.fetch('chain_id'))
        else
          expect_chain_done(services, response, label: 'change DNS source')
        end
        response
      end

      def set_smoke_enabled(enabled)
        response = update_dns_zone_runtime(
          services, admin_user_id: admin_user_id,
          dns_zone_id: smoke_ids.fetch('zone_id'), attrs: { enabled: enabled }
        )
        expect_chain_done(services, response, label: "zone enabled=#{enabled}")
        assert_node_metadata
      end

      def latch_snapshot
        _, output = dns.succeeds("cat #{LATCH_FILE}")
        JSON.parse(output)
      end

      def wait_for_axfr_gate
        wait_until_block_succeeds(name: 'real forced AXFR waits at fixture gate') do
          dns.succeeds("pgrep -f '^dns-smoke-blocked-axfr$'")
          true
        end
      end

      def emit_invalid_zone
        [
          "0x7b91dee53042: transfer of '#{ZONE_NAME.delete_suffix('.')}/IN' from #{PRIMARY_ADDR}#53: connected",
          "zone #{ZONE_NAME.delete_suffix('.')}/IN: transferred zone has no NS records"
        ].each do |message|
          dns.succeeds("#{Shellwords.join(['printf', "%s\n", message])} | ${pkgs.systemd}/bin/systemd-cat -t named")
        end
      end

      def wait_for_invalid_smoke_evidence(injected_at:, after_key:, generation:)
        wait_until_block_succeeds(name: 'API commits this invalid-zone observation', timeout: 60) do
          snapshot = smoke_snapshot
          state = snapshot.fetch('state')
          expect(state).not_to be_nil
          expect(snapshot.fetch('generation')).to eq(generation)
          expect(state.fetch('generation')).to eq(generation)
          expect(state.fetch('status')).to eq('failed')
          expect(state.fetch('reason_code')).to eq('invalid_zone')
          expect(state.fetch('event_key')).not_to eq(after_key)
          expect(state.fetch('reason_observed_at')).not_to be_nil
          expect(state.fetch('reason_observed_at')).to be >= injected_at
          snapshot
        end
      end

      def smoke_path_row
        services.mariadb_json_rows(sql: <<~SQL).first
          SELECT JSON_OBJECT(
            'status', s.status, 'attempt_kind', s.last_attempt_kind,
            'event_key', s.last_event_key,
            'generation', s.configuration_generation,
            'zone_generation', z.primary_transfer_generation,
            'attempt_at', TIMESTAMPDIFF(SECOND, '1970-01-01 00:00:00', s.last_attempt_at),
            'success_at', TIMESTAMPDIFF(SECOND, '1970-01-01 00:00:00', s.last_success_at)
          )
          FROM dns_server_zone_primary_transfer_states s
          JOIN dns_server_zones sz ON sz.id = s.dns_server_zone_id
          JOIN dns_zones z ON z.id = sz.dns_zone_id
          WHERE s.dns_server_zone_id = #{Integer(smoke_ids.fetch('server_zone_id'))}
            AND s.dns_zone_transfer_id = #{Integer(smoke_ids.fetch('transfer_id'))}
        SQL
      end

      def assert_new_full_bind_recovery(snapshot, after_log_id:, enabled_at:)
        state = snapshot.fetch('state')
        return unless state && state.fetch('status') == 'success'

        expect(state.fetch('generation').b).to eq(snapshot.fetch('generation').b)
        expect(state.fetch('evidence_current')).to be(true)
        # BIND may legitimately transfer again when the zone is re-enabled.
        # Logs have no generation column; current-state admission and this
        # exact endpoint's new transfer identity supply the matching evidence.
        row = services.mariadb_json_rows(sql: <<~SQL).first
          SELECT JSON_OBJECT('id', id, 'event_key', event_key)
          FROM dns_server_zone_transfer_logs
          WHERE dns_server_zone_id = #{Integer(smoke_ids.fetch('server_zone_id'))}
            AND dns_zone_transfer_id = #{Integer(smoke_ids.fetch('transfer_id'))}
            AND status = 0 AND attempt_kind = 0
            AND id > #{Integer(after_log_id)}
            AND TIMESTAMPDIFF(SECOND, '1970-01-01 00:00:00', event_at) >= #{Integer(enabled_at)}
          ORDER BY id DESC LIMIT 1
        SQL
        expect(row).not_to be_nil
        expect(row.fetch('event_key')).not_to be_empty
        assert_node_metadata(snapshot)
      end

      def wait_for_committed_smoke_axfr(after_key:, released_at:, generation:)
        wait_until_block_succeeds(name: 'committed current-path AXFR after gate release', timeout: 60) do
          row = smoke_path_row
          expect(row).not_to be_nil
          expect(row.fetch('status')).to eq(1)
          expect(row.fetch('attempt_kind')).to eq(5)
          expect(row.fetch('generation').b).to eq(generation.b)
          expect(row.fetch('zone_generation').b).to eq(generation.b)
          expect(row.fetch('event_key')).not_to eq(after_key)
          expect(row.fetch('success_at')).to eq(row.fetch('attempt_at'))
          %w[attempt_at success_at].each do |field|
            expect(row.fetch(field)).not_to be_nil
            expect(row.fetch(field).to_f).to be >= released_at
          end
          row
        end
      end

      def with_quiescent_probes
        dns.succeeds('systemctl stop vpsadmin-nodectld.service', timeout: 60)
        wait_until_block_succeeds(name: 'all isolated probes have stopped') do
          _, output = dns.succeeds("systemctl list-units --type=service --state=running --no-legend 'vpsadmin-dns-transfer-probe-*'")
          expect(output.strip).to eq("")
          true
        end
        # Producer is stopped. Drain its actual observation queue before aging
        # synthetic timestamps; no old in-flight success may undo the fixture.
        wait_until_block_succeeds(name: 'DNS observations drained') do
          _, output = services.succeeds('rabbitmqctl -q list_queues -p vpsadmin_test name messages --formatter json')
          rows = JSON.parse(output).select { |row| row.fetch('name').include?('dns_transfer_logs') }
          expect(rows).not_to be_empty
          expect(rows.map { |row| row.fetch('messages') }).to all(eq(0))
          true
        end
        # Auto-ack delivery can precede its database write. Stop the sole
        # consumer after draining so no in-flight callback can race aging.
        services.succeeds('systemctl stop vpsadmin-supervisor.service', timeout: 60)
        yield
      ensure
        services.succeeds('systemctl start vpsadmin-supervisor.service', timeout: 60)
        services.wait_for_service('vpsadmin-supervisor.service')
        restart_nixos_nodectld(dns)
        wait_for_nixos_nodectld(dns)
      end

      def age_smoke_evidence(minutes)
        services.api_ruby_json(code: <<~RUBY)
          state = DnsServerZonePrimaryTransferState.find_by!(
            dns_server_zone_id: #{Integer(smoke_ids.fetch('server_zone_id'))},
            dns_zone_transfer_id: #{Integer(smoke_ids.fetch('transfer_id'))}
          )
          old = #{Integer(minutes)}.minutes.ago
          attrs = { last_attempt_at: old }
          if state.success?
            attrs[:last_success_at] = old
          else
            attrs.merge!(last_failure_at: old, reason_observed_at: old, failed_since: old)
          end
          state.update!(attrs)
          puts JSON.dump(status: true)
        RUBY
        snapshot = smoke_snapshot
        expect(snapshot.fetch('state').fetch('evidence_current')).to be(false)
        expect(snapshot.fetch('aggregate')).to eq('pending')
        expect(snapshot.fetch('pending')).to eq(1)
        expect(snapshot.fetch('recovered')).to be_nil
        # Exercise the public projections as well as the model/aggregate query.
        _, paths = services.vpsadminctl.succeeds(
          args: ['dns_server_zone_primary_transfer_state', 'index'],
          parameters: { dns_zone: smoke_ids.fetch('zone_id') }
        )
        expect(paths.fetch('dns_server_zone_primary_transfer_states').map { |row| row.fetch('evidence_current') }).to eq([false])
        _, transfer = services.vpsadminctl.succeeds(args: ['dns_zone_transfer', 'show', smoke_ids.fetch('transfer_id').to_s])
        expect(transfer.fetch('dns_zone_transfer').fetch('transfer_check_status')).to eq('pending')
        snapshot
      end

      def owned_endpoint_snapshot
        services.api_ruby_json(code: <<~RUBY)
          ip = IpAddress.find(#{Integer(smoke_ids.fetch('ip_id'))})
          host = HostIpAddress.find_by(id: #{Integer(smoke_ids.fetch('host_ip_id'))})
          transfer = DnsZoneTransfer.find_by(id: #{Integer(smoke_ids.fetch('transfer_id'))})
          config = EnvironmentUserConfig.find_by!(
            user_id: #{Integer(admin_user_id)}, environment_id: Node.find(#{DNS_ID}).location.environment_id
          )
          puts JSON.dump(
            owner: ip.user_id, charge: ip.charged_environment_id,
            netif: ip.network_interface_id, host: host&.id, transfer: transfer&.id,
            tsig: transfer&.dns_tsig_key_id, use: config.public_send(ip.cluster_resource).to_i,
            generation: DnsZone.find(#{Integer(smoke_ids.fetch('zone_id'))}).primary_transfer_generation
          )
        RUBY
      end

      before(:suite) do
        services.start
        services.wait_for_vpsadmin_api
        services.wait_for_service('vpsadmin-rabbitmq-setup.service')
        services.wait_for_service('vpsadmin-supervisor.service')
        [primary, dns].each(&:start)
        [primary, dns].each { |machine| machine.wait_for_service('bind.service') }
        wait_for_nixos_nodectld(dns)
        wait_for_dns_node_ready(services, DNS_ID)
        services.unlock_transaction_signing_key(passphrase: 'test')
        dns.succeeds("ip address add #{ALIAS_ADDR}/24 dev eth1")
      end

      describe 'secondary lifecycle smoke', order: :defined do
        it 'round trips configuration and restores API and node originals after real rollback' do
          server = create_dns_server_runtime(services, admin_user_id: admin_user_id, node_id: DNS_ID, name: 'ns.secondary-lifecycle.test')
          zone = create_dns_zone_runtime(services, admin_user_id: admin_user_id, name: ZONE_NAME, source: 'external_source')
          peer = services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}
            node = Node.find(#{DNS_ID})
            network = Network.create!(
              address: '192.168.10.0', prefix: 24, label: 'Lifecycle primary',
              ip_version: 4, role: :private_access, managed: true,
              split_access: :no_access, split_prefix: 32, purpose: :vps,
              primary_location: node.location
            )
            LocationNetwork.create!(location: node.location, network: network, primary: true, priority: 10, autopick: false, userpick: true)
            ip = IpAddress.register(IPAddress.parse(#{PRIMARY_ADDR.inspect} + '/32'), network: network, user: nil, prefix: 32, size: 1)
            # Supported claim path establishes ownership AND quota provenance.
            ip.do_update(user: User.current, environment: node.location.environment)
            key = DnsTsigKey.create!(name: #{KEY_NAME.inspect}, algorithm: 'hmac-sha256', secret: '${keySecret}')
            transfer = DnsZoneTransfer.new(
              dns_zone: DnsZone.find(#{Integer(zone.fetch('id'))}),
              host_ip_address: ip.host_ip_addresses.first,
              peer_type: :primary_type, dns_tsig_key: key
            )
            chain, transfer = TransactionChains::DnsZoneTransfer::Create.fire(transfer)
            puts JSON.dump(ip_id: ip.id, host_ip_id: transfer.host_ip_address_id, transfer_id: transfer.id, chain_id: chain&.id)
          RUBY
          expect_chain_done(services, peer, label: 'create primary') if peer.fetch('chain_id')
          server_zone = create_dns_server_zone_runtime(
            services, admin_user_id: admin_user_id, dns_zone_id: zone.fetch('id'),
            dns_server_id: server.fetch('id'), zone_type: 'secondary_type'
          )
          expect_chain_done(services, server_zone, label: 'create secondary')
          @smoke_ids = peer.merge('zone_id' => zone.fetch('id'), 'server_id' => server.fetch('id'), 'server_zone_id' => server_zone.fetch('id'))
          initial = wait_for_smoke_probe(status: 'success')
          set_smoke_enabled(false)
          expect(smoke_snapshot.fetch('state')).to be_nil
          set_smoke_enabled(true)
          enabled = wait_for_smoke_probe(status: 'success')
          expect(enabled.fetch('generation')).not_to eq(initial.fetch('generation'))
          [ALIAS_ADDR, DNS_ADDR].each do |addr|
            previous = smoke_snapshot
            update_smoke_source(addr)
            current = wait_for_smoke_probe(status: 'success')
            expect(current.fetch('source')).to eq(addr)
            expect(current.fetch('generation')).not_to eq(previous.fetch('generation'))
          end
          original = assert_node_metadata
          update_smoke_source(ALIAS_ADDR, rollback: true)
          restored = wait_for_smoke_probe(status: 'success', after_key: original.fetch('state').fetch('event_key'))
          expect(restored.slice('generation', 'tracking', 'source', 'enabled')).to eq(original.slice('generation', 'tracking', 'source', 'enabled'))
        end

        it 'retains AXFR across disable and restart, and ages real evidence into pending' do
          key = "#{smoke_ids.fetch('server_zone_id')}:#{smoke_ids.fetch('transfer_id')}"
          previous = wait_for_smoke_probe(status: 'success')
          dns.succeeds('touch /run/dns-smoke-block-axfr')
          begin
            # Journal event times have whole-second precision on the node.
            _, injection_time = dns.succeeds('date +%s')
            emit_invalid_zone
            wait_for_axfr_gate
            expect(latch_snapshot.fetch(key).fetch('needs_axfr')).to be(true)
            # A local latch or auto-acked empty queue is not an API commit.
            wait_for_invalid_smoke_evidence(
              injected_at: Integer(injection_time.strip),
              after_key: previous.fetch('state').fetch('event_key'),
              generation: previous.fetch('generation')
            )
            # This is genuine slow/content evidence, not a manufactured state.
            with_quiescent_probes do
              expect(smoke_snapshot.fetch('state').fetch('reason_code')).to eq('invalid_zone')
              age_smoke_evidence(76)
            end
            wait_for_axfr_gate
            set_smoke_enabled(false)
            # Scheduler ticks every second. Wait through several ticks, then
            # assert cancellation AND retained configured-identity latch.
            sleep 3
            wait_until_block_succeeds(name: 'disabled scheduler cancels gated AXFR') do
              dns.fails("pgrep -f '^dns-smoke-blocked-axfr$'")
              true
            end
            expect(latch_snapshot.fetch(key).fetch('needs_axfr')).to be(true)
            restart_nixos_nodectld(dns)
            wait_for_nixos_nodectld(dns)
            sleep 3
            expect(latch_snapshot.fetch(key).fetch('needs_axfr')).to be(true)
            log_cursor = services.mariadb_scalar(sql: <<~SQL).to_i
              SELECT COALESCE(MAX(id), 0) FROM dns_server_zone_transfer_logs
              WHERE dns_server_zone_id = #{Integer(smoke_ids.fetch('server_zone_id'))}
                AND dns_zone_transfer_id = #{Integer(smoke_ids.fetch('transfer_id'))}
            SQL
            _, enabled_time = dns.succeeds('date +%s')
            set_smoke_enabled(true)
            wait_for_axfr_gate
            expect(latch_snapshot.fetch(key).fetch('needs_axfr')).to be(true)
            reenabled = smoke_snapshot
            assert_new_full_bind_recovery(
              reenabled, after_log_id: log_cursor, enabled_at: Integer(enabled_time.strip)
            )
            before_release = smoke_path_row
            release_key = before_release && before_release.fetch('event_key')
            _, release_time = dns.succeeds('date +%s')
          ensure
            dns.succeeds('rm -f /run/dns-smoke-block-axfr')
          end
          # Ruby API startup can exceed the healthy retry interval. Capture the
          # real transient AXFR state using the existing lightweight SQL helper.
          axfr = wait_for_committed_smoke_axfr(
            after_key: release_key, released_at: Integer(release_time.strip),
            generation: reenabled.fetch('generation')
          )
          puts JSON.dump(committed_axfr: axfr)
          wait_until_block_succeeds(name: 'validated AXFR clears latch') do
            expect(latch_snapshot).not_to have_key(key)
            true
          end
          wait_for_smoke_probe(status: 'success')
          aged = nil
          with_quiescent_probes { aged = age_smoke_evidence(76) }
          wait_for_smoke_probe(status: 'success', after_key: aged.fetch('state').fetch('event_key'))

          primary.succeeds('systemctl stop bind.service')
          begin
            failed = wait_for_smoke_probe(status: 'failed')
            expect(%w[connection_failed timeout]).to include(failed.fetch('state').fetch('reason_code'))
            with_quiescent_probes { age_smoke_evidence(16) }
          ensure
            primary.succeeds('systemctl start bind.service')
            primary.wait_for_service('bind.service')
          end
          wait_for_smoke_probe(status: 'success', kind: 'ixfr_probe', after_key: failed.fetch('state').fetch('event_key'))
        end

        it 'keeps the owned endpoint on real route detach and removes BIND references on disown' do
          node.start
          wait_for_running_nodectld(node)
          pool = create_pool(services, node_id: node1_id, label: 'dns-lifecycle', filesystem: primary_pool_fs, role: 'hypervisor')
          wait_for_pool_online(services, pool.fetch('id'))
          wait_for_node_ready(services, node1_id)
          vps = create_vps(services, admin_user_id: admin_user_id, node_id: node1_id, hostname: 'dns-lifecycle', start: false)
          netif = create_veth_routed_netif(services, admin_user_id: admin_user_id, vps_id: vps.fetch('id'), name: 'eth1')
          expect_chain_done(services, netif, label: 'create stopped VPS interface')
          before = owned_endpoint_snapshot
          expect(before.fetch('owner')).to eq(admin_user_id)
          expect(before.fetch('charge')).not_to be_nil
          expect(before.fetch('use')).to be >= 1
          added = add_route_to_netif(services, admin_user_id: admin_user_id, netif_id: netif.fetch('netif_id'), ip_id: smoke_ids.fetch('ip_id'))
          expect_chain_done(services, added, label: 'attach owned primary route', expected_handles: [tx_types(services).fetch('netif_add_route')])
          wait_for_route_present(node, vps_id: vps.fetch('id'), name: 'eth1', cidr: "#{PRIMARY_ADDR}/32")
          attached = owned_endpoint_snapshot
          expect(attached.fetch('netif')).to eq(netif.fetch('netif_id'))
          removed = del_route_from_netif(services, admin_user_id: admin_user_id, netif_id: netif.fetch('netif_id'), ip_id: smoke_ids.fetch('ip_id'))
          expect_chain_done(services, removed, label: 'detach owned primary route', expected_handles: [tx_types(services).fetch('netif_del_route')])
          wait_for_route_absent(node, vps_id: vps.fetch('id'), name: 'eth1', cidr: "#{PRIMARY_ADDR}/32")
          detached = owned_endpoint_snapshot
          expect(detached.fetch('netif')).to be_nil
          expect(detached.except('netif')).to eq(before.except('netif'))
          expect(named_config_text(dns)).to include("#{PRIMARY_ADDR} key #{KEY_NAME};")
          post_detach = wait_for_smoke_probe(status: 'success')
          wait_for_smoke_probe(status: 'success', after_key: post_detach.fetch('state').fetch('event_key'))
          node.succeeds("test \"$(osctl ct show -H -o state #{Integer(vps.fetch('id'))})\" = stopped")
          disowned = services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}
            chain, = IpAddress.find(#{Integer(smoke_ids.fetch('ip_id'))}).do_update(user: nil)
            puts JSON.dump(chain_id: chain.id)
          RUBY
          expect_chain_done(services, disowned, label: 'disown primary and clean DNS configuration')
          wait_for_chain_locks_released(services, disowned.fetch('chain_id'))
          final = owned_endpoint_snapshot
          expect(final.values_at('owner', 'charge', 'transfer', 'tsig')).to eq([nil, nil, nil, nil])
          expect(final.fetch('host')).to eq(before.fetch('host'))
          expect(final.fetch('use')).to eq(before.fetch('use') - 1)
          cleanup = services.api_ruby_json(code: <<~RUBY)
            puts JSON.dump(states: DnsServerZonePrimaryTransferState.where(dns_zone_transfer_id: #{Integer(smoke_ids.fetch('transfer_id'))}).count)
          RUBY
          expect(cleanup.fetch('states')).to eq(0)
          wait_until_block_succeeds(name: 'BIND endpoint and TSIG removed') do
            config = named_config_text(dns)
            expect(config).not_to include(PRIMARY_ADDR)
            expect(config).not_to include(KEY_NAME)
            true
          end
        end
      end
    '';
  }
)
