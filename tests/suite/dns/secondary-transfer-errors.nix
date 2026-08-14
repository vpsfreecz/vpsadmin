import ../../make-test.nix (
  {
    pkgs,
    ...
  }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    dnsSeed = import ../../../api/db/seeds/test-dns-server-node.nix;
    dnsNode1 = dnsSeed.dnsNode;
    dnsNode2 = rec {
      id = 302;
      name = "vpsadmin-dns2";
      domain = "${name}.${seed.location.domain}";
      ipAddr = "192.168.10.32";
    };
    common = import ../tasks/common.nix {
      adminUserId = adminUser.id;
      node1Id = dnsNode1.id;
      node2Id = dnsNode2.id;
      manageCluster = false;
    };
    baseMachines = import ../../machines/dns-server-node.nix args;
    primary1Addr = "192.168.10.50";
    primary2Addr = "192.168.10.51";
    zoneName = "secondary-errors.test.";
    zoneSerial = "2026081301";
    primaryZone = pkgs.writeText "${zoneName}zone" ''
      $ORIGIN ${zoneName}
      $TTL 60
      @ IN SOA ns1.${zoneName} hostmaster.${zoneName} ${zoneSerial} 3600 60 604800 60
      @ IN NS ns1.${zoneName}
      @ IN NS ns2.${zoneName}
      ns1 IN A ${primary1Addr}
      ns2 IN A ${primary2Addr}
      www IN A 192.0.2.80
    '';
    probeSettings = {
      status_interval = 2;
      transfer_probe_interval = 60;
      transfer_probe_failure_interval = 3;
      transfer_probe_timeout = 3;
      transfer_probe_axfr_timeout = 10;
      transfer_probe_axfr_max_bytes = 16 * 1024 * 1024;
      transfer_probe_concurrency = 5;
    };
    probeAuditModule =
      { pkgs, ... }:
      let
        # Every real probe in this scenario first proves that systemd assigned
        # a non-root dynamic UID, hid nodectld state and blocked the other
        # reachable primary at the cgroup network boundary. It then runs the
        # packaged worker with the unchanged stdin/stdout contract.
        probeAuditScript = pkgs.writeText "dns-transfer-probe-audit.rb" ''
          require 'json'
          require 'open3'
          require 'socket'

          payload = $stdin.read
          job = JSON.parse(payload)
          abort 'probe worker is running as root' if Process.uid.zero?

          begin
            Dir.entries('/var/lib/nodectld')
            abort 'probe worker can read nodectld state'
          rescue SystemCallError
            # Expected from DynamicUser plus InaccessiblePaths.
          end

          blocked_addr =
            job.fetch('primary_addr') == '${primary1Addr}' ? '${primary2Addr}' : '${primary1Addr}'
          begin
            socket = Socket.tcp(blocked_addr, 53, connect_timeout: 1)
            socket.close
            abort 'probe worker can contact a non-selected primary'
          rescue SystemCallError, IO::TimeoutError
            # Expected from IPAddressDeny=any plus the one selected allow rule.
          end

          # Keep one path observable long enough for the runtime-removal
          # example to prove that nodectld stops the real transient unit.
          sleep 15 if job.fetch('primary_addr') == '${primary2Addr}'

          stdout, stderr, status = Open3.capture3(
            '${pkgs.nodectld}/bin/vpsadmin-dns-transfer-probe',
            stdin_data: payload
          )
          $stdout.write(stdout)
          $stderr.write(stderr)
          exit(status.exitstatus)
        '';
        probeAuditWorker = pkgs.writeShellScriptBin "vpsadmin-dns-transfer-probe-audit" ''
          exec ${pkgs.ruby}/bin/ruby ${probeAuditScript}
        '';
      in
      {
        vpsadmin.nodectld.settings.dns_server.transfer_probe_worker_command =
          pkgs.lib.mkForce "${probeAuditWorker}/bin/vpsadmin-dns-transfer-probe-audit";
      };
    mkPrimary =
      {
        hostName,
        address,
        allowTransfer,
      }:
      {
        spin = "nixos";
        networks = [ { type = "socket"; } ];
        config = {
          networking = {
            inherit hostName;
            firewall.allowedTCPPorts = [ 53 ];
            firewall.allowedUDPPorts = [ 53 ];
            interfaces.eth0 = {
              useDHCP = false;
              ipv4.addresses = [
                {
                  inherit address;
                  prefixLength = 24;
                }
              ];
            };
          };

          virtualisation = {
            memorySize = 768;
            cores = 1;
          };

          environment.systemPackages = [ pkgs.bind ];
          systemd.tmpfiles.rules = [ "d /var/named 0755 named named -" ];

          services.bind = {
            enable = true;
            package = pkgs.bind;
            directory = "/var/named";
            ipv4Only = true;
            listenOn = [ address ];
            listenOnIpv6 = [ ];
            forwarders = [ ];
            cacheNetworks = [ ];
            configFile = pkgs.writeText "${hostName}-named.conf" ''
              include "/etc/bind/rndc.key";

              controls {
                inet 127.0.0.1 port 953 allow { 127.0.0.1; } keys { "rndc-key"; };
              };

              options {
                directory "/var/named";
                pid-file "/run/named/named.pid";
                session-keyfile "/run/named/session.key";
                listen-on port 53 { ${address}; };
                listen-on-v6 { none; };
                allow-query { any; };
                recursion no;
                dnssec-validation no;
              };

              zone "${zoneName}" {
                type primary;
                file "${primaryZone}";
                allow-transfer { ${pkgs.lib.concatMapStringsSep " " (addr: "${addr};") allowTransfer} };
                notify no;
              };
            '';
          };
        };
      };
  in
  {
    name = "dns-secondary-transfer-errors";
    description = ''
      Exercise stock-BIND transfer diagnostics and active transfer-readiness
      probes across multiple managed secondaries and user primaries.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "network"
    ];

    machines = baseMachines // {
      services = baseMachines.services // {
        config = {
          imports = [ baseMachines.services.config ];
          vpsadmin.test = {
            socketPeers.${dnsNode2.name} = dnsNode2.ipAddr;
            rabbitmqNodeUsers = [ dnsNode2.domain ];
          };
        };
      };

      dns = baseMachines.dns // {
        config = {
          imports = [
            baseMachines.dns.config
            probeAuditModule
          ];
          vpsadmin = {
            nodectld.settings.dns_server = probeSettings;
            test.dnsServer.socketPeers.${dnsNode2.name} = dnsNode2.ipAddr;
          };
        };
      };

      dns2 = {
        spin = "nixos";
        networks = [
          { type = "user"; }
          { type = "socket"; }
        ];
        config = {
          imports = [
            ../../configs/nixos/vpsadmin-dns-server.nix
            probeAuditModule
          ];
          vpsadmin = {
            nodectld.settings.dns_server = probeSettings;
            test.dnsServer = {
              socketAddress = dnsNode2.ipAddr;
              servicesAddress = "192.168.10.10";
              nodeId = dnsNode2.id;
              nodeName = dnsNode2.name;
              locationDomain = seed.location.domain;
              socketPeers.${dnsNode1.name} = dnsNode1.ipAddr;
            };
          };
        };
      };

      primary1 = mkPrimary {
        hostName = "user-primary1";
        address = primary1Addr;
        allowTransfer = [ dnsNode1.ipAddr ];
      };

      # Both user primaries intentionally omit dnsNode2. It can obtain the zone
      # only from the managed dnsNode1 peer, while the active checks must still
      # expose both missing direct-transfer ACL entries.
      primary2 = mkPrimary {
        hostName = "user-primary2";
        address = primary2Addr;
        allowTransfer = [ dnsNode1.ipAddr ];
      };
    };

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      PRIMARY1_ADDR = '${primary1Addr}'
      PRIMARY2_ADDR = '${primary2Addr}'
      DNS_NODE1_ADDR = '${dnsNode1.ipAddr}'
      DNS_NODE2_ID = ${toString dnsNode2.id}
      DNS_NODE2_NAME = '${dnsNode2.name}'
      DNS_NODE2_ADDR = '${dnsNode2.ipAddr}'
      ZONE_NAME = '${zoneName}'
      ZONE_NAME_BARE = ZONE_NAME.delete_suffix('.')
      ZONE_SERIAL = ${zoneSerial}

      def create_second_dns_node(services)
        services.api_ruby_json(code: <<~RUBY)
          template = Node.find(#{Integer(node1_id)})
          node = Node.find_or_initialize_by(id: #{DNS_NODE2_ID})
          node.assign_attributes(
            name: #{DNS_NODE2_NAME.inspect},
            location: template.location,
            ip_addr: #{DNS_NODE2_ADDR.inspect},
            max_vps: 0,
            cpus: 1,
            total_memory: 1024,
            total_swap: 0,
            role: :dns_server,
            hypervisor_type: nil
          )
          node.save!
          puts JSON.dump(id: node.id)
        RUBY
      end

      def create_primary_host_ip(services, admin_user_id:, node_id:, addr:)
        services.api_ruby_json(code: <<~RUBY)
          node = Node.find(#{Integer(node_id)})
          user = User.find(#{Integer(admin_user_id)})
          network = Network.find_or_initialize_by(address: '192.168.10.0', prefix: 24)
          network.assign_attributes(
            label: 'DNS integration primaries',
            ip_version: 4,
            role: :private_access,
            managed: true,
            split_access: :no_access,
            split_prefix: 32,
            purpose: :vps,
            primary_location: node.location
          )
          network.save! if network.new_record? || network.changed?

          loc_net = LocationNetwork.find_or_initialize_by(location: node.location, network: network)
          loc_net.assign_attributes(primary: true, priority: 10, autopick: true, userpick: true)
          loc_net.save! if loc_net.new_record? || loc_net.changed?

          ip = IpAddress.find_by(ip_addr: #{addr.inspect})
          ip ||= IpAddress.register(
            IPAddress.parse(#{addr.inspect} + '/32'),
            network: network,
            user: user,
            location: node.location,
            prefix: 32,
            size: 1,
            allocate: false
          )
          ip.update!(user: user) if ip.user != user
          host_ip = ip.host_ip_addresses.first || HostIpAddress.create!(
            ip_address: ip,
            ip_addr: ip.ip_addr,
            order: nil
          )

          puts JSON.dump(host_ip_id: host_ip.id, addr: host_ip.ip_addr)
        RUBY
      end

      def fixture_ids(services)
        services.api_ruby_json(code: <<~RUBY)
          zone = DnsZone.find_by!(name: #{ZONE_NAME.inspect})
          server_zones = zone.dns_server_zones.includes(dns_server: :node).to_h do |server_zone|
            [server_zone.dns_server.node_id.to_s, server_zone.id]
          end
          transfers = zone.dns_zone_transfers.primary_type.includes(:host_ip_address).to_h do |transfer|
            [transfer.ip_addr, transfer.id]
          end

          puts JSON.dump(
            zone_id: zone.id,
            server_zones: server_zones,
            transfers: transfers
          )
        RUBY
      end

      def destroy_dns_zone_runtime(services, admin_user_id:, dns_zone_id:)
        services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          zone = DnsZone.find(#{Integer(dns_zone_id)})
          chain = VpsAdmin::API::Operations::DnsZone::DestroyUser.run(zone)
          puts JSON.dump(chain_id: chain&.id, id: zone.id)
        RUBY
      end

      def path_snapshot(services, server_zone_id:, transfer_id:)
        services.api_ruby_json(code: <<~RUBY)
          server_zone = DnsServerZone.find(#{Integer(server_zone_id)})
          transfer = DnsZoneTransfer.find(#{Integer(transfer_id)})
          state = DnsServerZonePrimaryTransferState.find_by(
            dns_server_zone: server_zone,
            dns_zone_transfer: transfer
          )
          logs = server_zone.dns_server_zone_transfer_logs.where(dns_zone_transfer: transfer)

          puts JSON.dump(
            state_id: state&.id,
            status: state&.status,
            failure_class: state&.failure_class,
            failed_since: state&.failed_since&.iso8601,
            last_failure_at: state&.last_failure_at&.iso8601,
            last_attempt_at: state&.last_attempt_at&.iso8601,
            last_attempt_kind: state&.last_attempt_kind,
            reason_code: state&.reason_code,
            primary_serial: state&.primary_serial,
            secondary_serial: state&.secondary_serial,
            alert_eligible: state && DnsServerZonePrimaryTransferState
              .alert_eligible_at(Time.current)
              .exists?(id: state.id),
            log_count: logs.count,
            reason_codes: logs.where.not(reason_code: nil).pluck(:reason_code),
            attempts: logs.pluck(:attempt_kind)
          )
        RUBY
      end

      def wait_for_path(
        services,
        server_zone_id:,
        transfer_id:,
        status:,
        failure_class: :unspecified,
        reason_code: :unspecified,
        attempt_kind: :unspecified
      )
        wait_until_block_succeeds(name: "transfer readiness path #{server_zone_id}:#{transfer_id}") do
          state = path_snapshot(
            services,
            server_zone_id: server_zone_id,
            transfer_id: transfer_id
          )
          expect(state.fetch('status')).to eq(status)
          expect(state.fetch('failure_class')).to eq(failure_class) unless failure_class == :unspecified
          expect(state.fetch('reason_code')).to eq(reason_code) unless reason_code == :unspecified
          expect(state.fetch('last_attempt_kind')).to eq(attempt_kind) unless attempt_kind == :unspecified
          state
        end
      end

      def matrix_snapshot(services)
        services.api_ruby_json(code: <<~RUBY)
          zone = DnsZone.find_by!(name: #{ZONE_NAME.inspect})
          rows = DnsServerZonePrimaryTransferState
            .joins(dns_server_zone: { dns_server: :node }, dns_zone_transfer: :host_ip_address)
            .where(dns_server_zones: { dns_zone_id: zone.id })
            .order('nodes.id', 'host_ip_addresses.ip_addr')
            .map do |state|
              {
                node_id: state.dns_server_zone.dns_server.node_id,
                primary_addr: state.dns_zone_transfer.ip_addr,
                status: state.status,
                failure_class: state.failure_class,
                reason_code: state.reason_code
              }
            end
          puts JSON.dump(rows: rows)
        RUBY
      end

      def emit_bind_logs(node, messages)
        messages.each do |message|
          printf_cmd = Shellwords.join(['printf', "%s\n", message])
          node.succeeds("#{printf_cmd} | ${pkgs.systemd}/bin/systemd-cat -t named")
        end
      end

      def wait_for_probe_unit(machine, primary_addr)
        wait_until_block_succeeds(name: "active isolated probe for #{primary_addr}") do
          _, output = machine.succeeds(<<~SH)
            for unit in $(systemctl list-units \
              --type=service --state=running --no-legend \
              'vpsadmin-dns-transfer-probe-*' | awk '{ print $1 }'); do
              if systemctl show --property=IPAddressAllow --value "$unit" \
                | grep -Fq #{Shellwords.escape(primary_addr)}; then
                printf '%s\\n' "$unit"
                exit 0
              fi
            done
            exit 1
          SH
          output.strip
        end
      end

      before(:suite) do
        services.start
        services.wait_for_vpsadmin_api
        services.wait_for_service('vpsadmin-rabbitmq-setup.service')
        services.wait_for_service('vpsadmin-supervisor.service')
        create_second_dns_node(services)
        services.succeeds(
          'systemctl restart vpsadmin-supervisor.service',
          timeout: 60
        )
        services.wait_for_service('vpsadmin-supervisor.service')

        [primary1, primary2, dns, dns2].each(&:start)
        [primary1, primary2, dns, dns2].each { |machine| machine.wait_for_service('bind.service') }
        [dns, dns2].each { |machine| wait_for_nixos_nodectld(machine) }
        wait_for_dns_node_ready(services, node1_id)
        wait_for_dns_node_ready(services, DNS_NODE2_ID)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'DNS secondary transfer readiness', order: :defined do
        it 'checks the complete matrix while the second secondary serves through its peer' do
          dns_servers = [
            create_dns_server_runtime(
              services,
              admin_user_id: admin_user_id,
              node_id: node1_id,
              name: 'ns1.secondary-errors.test'
            ),
            create_dns_server_runtime(
              services,
              admin_user_id: admin_user_id,
              node_id: DNS_NODE2_ID,
              name: 'ns2.secondary-errors.test'
            )
          ]
          dns_servers.each do |server|
            services.api_ruby_json(code: <<~RUBY)
              DnsServer.find(#{Integer(server.fetch('id'))}).update!(
                user_dns_zone_type: :secondary_type
              )
              puts JSON.dump(status: true)
            RUBY
          end

          zone = create_dns_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            name: ZONE_NAME,
            source: 'external_source'
          )
          [PRIMARY1_ADDR, PRIMARY2_ADDR].each do |addr|
            host_ip = create_primary_host_ip(
              services,
              admin_user_id: admin_user_id,
              node_id: node1_id,
              addr: addr
            )
            create_dns_zone_transfer_runtime(
              services,
              admin_user_id: admin_user_id,
              dns_zone_id: zone.fetch('id'),
              host_ip_id: host_ip.fetch('host_ip_id'),
              peer_type: 'primary_type'
            )
          end

          dns_servers.each do |server|
            created = create_dns_server_zone_runtime(
              services,
              admin_user_id: admin_user_id,
              dns_zone_id: zone.fetch('id'),
              dns_server_id: server.fetch('id'),
              zone_type: 'secondary_type'
            )
            expect_chain_done(services, created, label: "create #{server.fetch('name')}")
          end

          ids = fixture_ids(services)
          wait_until_block_succeeds(name: 'four transfer readiness paths') do
            rows = matrix_snapshot(services).fetch('rows')
            expect(rows).to match_array([
              {
                'node_id' => node1_id,
                'primary_addr' => PRIMARY1_ADDR,
                'status' => 'success',
                'failure_class' => nil,
                'reason_code' => nil
              },
              {
                'node_id' => DNS_NODE2_ID,
                'primary_addr' => PRIMARY1_ADDR,
                'status' => 'failed',
                'failure_class' => 'primary',
                'reason_code' => 'refused'
              },
              {
                'node_id' => node1_id,
                'primary_addr' => PRIMARY2_ADDR,
                'status' => 'success',
                'failure_class' => nil,
                'reason_code' => nil
              },
              {
                'node_id' => DNS_NODE2_ID,
                'primary_addr' => PRIMARY2_ADDR,
                'status' => 'failed',
                'failure_class' => 'primary',
                'reason_code' => 'refused'
              }
            ])
            true
          end

          [
            [dns, DNS_NODE1_ADDR],
            [dns2, DNS_NODE2_ADDR]
          ].each do |machine, server_addr|
            wait_for_dns_answer(
              machine,
              server: server_addr,
              zone_name: ZONE_NAME,
              record: {
                name: 'www',
                record_type: 'A',
                answer: '192.0.2.80'
              }
            )
          end

          refused = path_snapshot(
            services,
            server_zone_id: ids.fetch('server_zones').fetch(DNS_NODE2_ID.to_s),
            transfer_id: ids.fetch('transfers').fetch(PRIMARY2_ADDR)
          )
          expect(refused.fetch('alert_eligible')).to be(false)
          expect(refused.fetch('attempts')).to include('transfer')
          expect(refused.fetch('reason_codes')).to include('refused')
        end

        it 'retains an invalid-zone BIND diagnostic until a validated AXFR recovers readiness' do
          ids = fixture_ids(services)
          server_zone_id = ids.fetch('server_zones').fetch(node1_id.to_s)
          transfer_id = ids.fetch('transfers').fetch(PRIMARY1_ADDR)

          pointer = '0x7b91dee53042'
          emit_bind_logs(dns, [
            "#{pointer}: transfer of '#{ZONE_NAME_BARE}/IN' from #{PRIMARY1_ADDR}#53: connected",
            "zone #{ZONE_NAME_BARE}/IN: transferred zone has no NS records"
          ])
          diagnostic = wait_until_block_succeeds(name: 'invalid-zone diagnostic is retained') do
            snapshot = path_snapshot(
              services,
              server_zone_id: server_zone_id,
              transfer_id: transfer_id
            )
            expect(snapshot.fetch('reason_codes')).to include('invalid_zone')
            expect(snapshot.fetch('attempts')).to include('transfer')
            snapshot
          end
          expect(diagnostic.fetch('reason_codes')).to include('invalid_zone')

          recovered = wait_for_path(
            services,
            server_zone_id: server_zone_id,
            transfer_id: transfer_id,
            status: 'success',
            failure_class: nil,
            reason_code: nil,
            attempt_kind: 'axfr_probe'
          )
          expect(recovered.fetch('primary_serial')).to eq(ZONE_SERIAL)
        end

        it 'detects a crashed primary continuously without claiming the served zone is down' do
          ids = fixture_ids(services)
          transfer_id = ids.fetch('transfers').fetch(PRIMARY1_ADDR)
          server_zone_id = ids.fetch('server_zones').fetch(node1_id.to_s)
          primary1.succeeds('systemctl stop bind.service')

          failed = wait_for_path(
            services,
            server_zone_id: server_zone_id,
            transfer_id: transfer_id,
            status: 'failed',
            failure_class: 'network'
          )
          expect(%w[connection_failed timeout]).to include(failed.fetch('reason_code'))
          expect(failed.fetch('alert_eligible')).to be(false)

          services.api_ruby_json(code: <<~RUBY)
            state = DnsServerZonePrimaryTransferState.find(#{Integer(failed.fetch('state_id'))})
            state.update!(failed_since: 25.hours.ago, alert_eligible_at: nil)
            puts JSON.dump(status: true)
          RUBY
          wait_until_block_succeeds(name: 'continuous primary outage becomes alertable') do
            repeated = path_snapshot(
              services,
              server_zone_id: server_zone_id,
              transfer_id: transfer_id
            )
            expect(repeated.fetch('status')).to eq('failed')
            expect(repeated.fetch('failure_class')).to eq('network')
            expect(repeated.fetch('alert_eligible')).to be(true)
            repeated
          end

          [
            [dns, DNS_NODE1_ADDR],
            [dns2, DNS_NODE2_ADDR]
          ].each do |machine, server_addr|
            wait_for_dns_answer(
              machine,
              server: server_addr,
              zone_name: ZONE_NAME,
              record: {
                name: 'www',
                record_type: 'A',
                answer: '192.0.2.80'
              }
            )
          end

          primary1.succeeds('systemctl start bind.service')
          primary1.wait_for_service('bind.service')
          recovered = wait_for_path(
            services,
            server_zone_id: server_zone_id,
            transfer_id: transfer_id,
            status: 'success',
            failure_class: nil,
            reason_code: nil,
            attempt_kind: 'ixfr_probe'
          )
          expect(recovered.fetch('alert_eligible')).to be(false)
        end

        it 'reconciles primary and zone changes without restarting nodectld' do
          ids = fixture_ids(services)
          zone_id = ids.fetch('zone_id')
          old_transfer_id = ids.fetch('transfers').fetch(PRIMARY2_ADDR)
          nodectld_pids = [dns, dns2].to_h do |machine|
            _, output = machine.succeeds(
              'systemctl show --property=MainPID --value vpsadmin-nodectld.service'
            )
            [machine, output.strip]
          end
          running_units = [dns, dns2].to_h do |machine|
            [machine, wait_for_probe_unit(machine, PRIMARY2_ADDR)]
          end

          destroyed = destroy_dns_zone_transfer_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_transfer_id: old_transfer_id
          )
          expect_chain_done(services, destroyed, label: 'remove runtime primary')
          running_units.each do |machine, unit|
            wait_until_block_succeeds(name: "cancelled isolated unit #{unit}") do
              machine.fails("systemctl is-active #{Shellwords.escape(unit)}")
              true
            end
          end
          wait_until_block_succeeds(name: 'removed primary paths disappear') do
            snapshot = services.api_ruby_json(code: <<~RUBY)
              puts JSON.dump(
                transfer_exists: DnsZoneTransfer.exists?(#{Integer(old_transfer_id)}),
                state_count: DnsServerZonePrimaryTransferState.where(
                  dns_zone_transfer_id: #{Integer(old_transfer_id)}
                ).count
              )
            RUBY
            expect(snapshot.fetch('transfer_exists')).to be(false)
            expect(snapshot.fetch('state_count')).to eq(0)
            snapshot
          end

          host_ip = create_primary_host_ip(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            addr: PRIMARY2_ADDR
          )
          created = create_dns_zone_transfer_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_id: zone_id,
            host_ip_id: host_ip.fetch('host_ip_id'),
            peer_type: 'primary_type'
          )
          expect_chain_done(services, created, label: 'add runtime primary')
          expect(created.fetch('id')).not_to eq(old_transfer_id)

          current_ids = fixture_ids(services)
          new_transfer_id = current_ids.fetch('transfers').fetch(PRIMARY2_ADDR)
          wait_for_path(
            services,
            server_zone_id: current_ids.fetch('server_zones').fetch(node1_id.to_s),
            transfer_id: new_transfer_id,
            status: 'success'
          )
          wait_for_path(
            services,
            server_zone_id: current_ids.fetch('server_zones').fetch(DNS_NODE2_ID.to_s),
            transfer_id: new_transfer_id,
            status: 'failed',
            failure_class: 'primary',
            reason_code: 'refused'
          )

          removed_zone = destroy_dns_zone_runtime(
            services,
            admin_user_id: admin_user_id,
            dns_zone_id: zone_id
          )
          expect_chain_done(services, removed_zone, label: 'remove runtime zone')
          removed = services.api_ruby_json(code: <<~RUBY)
            puts JSON.dump(
              zone_exists: DnsZone.exists?(#{Integer(zone_id)}),
              state_count: DnsServerZonePrimaryTransferState.where(
                dns_server_zone_id: #{current_ids.fetch('server_zones').values.map { |id| Integer(id) }.inspect}
              ).count
            )
          RUBY
          expect(removed.fetch('zone_exists')).to be(false)
          expect(removed.fetch('state_count')).to eq(0)

          [['dns', dns], ['dns2', dns2]].each do |name, machine|
            wait_until_block_succeeds(name: "zone removed from #{name}") do
              _, config = machine.succeeds('cat /var/named/vpsadmin/named.conf')
              expect(config).not_to include(%(zone "#{ZONE_NAME_BARE}"))
              _, output = machine.succeeds(
                'systemctl show --property=MainPID --value vpsadmin-nodectld.service'
              )
              expect(output.strip).to eq(nodectld_pids.fetch(machine))
              true
            end
          end
        end
      end
    '';
  }
)
