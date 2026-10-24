import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ../storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };
  in
  {
    name = "vps-autostart-monitoring";

    description = ''
      Accept the first complete boot inventory asynchronously and retain starts
      through nodectld downtime and an osctld restart, without later arrivals.
    '';

    tags = [
      "ci"
      "monitoring"
      "vpsadmin"
      "vps"
    ];

    machines = import ../../machines/cluster/1-node.nix (
      args
      // {
        extraModules.nodes.node = {
          vpsadmin.nodectld.settings = {
            exporter.interval = 2;
            vpsadmin.vps_status_interval = 5;
          };
        };
      }
    );

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      def boot_autostart_ledger(machine)
        _, output = machine.succeeds('cat /run/nodectl/boot-autostart.json', timeout: 30)
        JSON.parse(output)
      end

      def state_history(machine, ever_running: false)
        command = 'osctl -j ct state-history'
        command += ' --ever-running' if ever_running
        _, output = machine.succeeds(command, timeout: 30)
        history = JSON.parse(output)
        expect(history.fetch('available')).to be(true)
        history
      end

      def wait_for_boot_check(machine, ids:, pending: [], after: 0)
        result = nil
        wait_until_block_succeeds(name: "boot auto-start check on #{machine.name}", timeout: 180) do
          ledger = boot_autostart_ledger(machine)
          expect(ledger.fetch('phase')).to eq('active')
          expect(ledger.fetch('obligations').map { |row| row.fetch('id') }).to contain_exactly(*ids)
          ledger.fetch('obligations').each do |row|
            expected = pending.include?(row.fetch('id')) ? 'pending' : 'fulfilled'
            expect(row.fetch('state')).to eq(expected)
            expect(row.fetch('reason')).to eq('running') unless expected == 'pending'
          end

          _, output = machine.succeeds('cat /run/metrics/nodectld.prom', timeout: 30)
          lines = output.lines.map(&:strip)
          expect(lines).to include(
            'nodectld_vps_boot_autostart_supported 1.0',
            'nodectld_vps_boot_autostart_check_success 1.0',
            'nodectld_vps_boot_autostart_state{state="active",reason="none"} 1.0'
          )
          expected_lines = ids.empty? ? [] : ["nodectld_vps_boot_autostart_expected{pool=\"tank\"} #{ids.length.to_f}"]
          expect(lines.grep(/^nodectld_vps_boot_autostart_expected\{/)).to eq(expected_lines)
          pending_lines = pending.map do |id|
            "nodectld_vps_boot_autostart_unsatisfied{pool=\"tank\",vps_id=\"#{id}\"} 1.0"
          end
          expect(lines.grep(/^nodectld_vps_boot_autostart_unsatisfied\{/)).to match_array(pending_lines)
          timestamp = Float(lines.find { |line| line.start_with?('nodectld_vps_boot_autostart_check_last_success_timestamp_seconds ') }.split.last)
          expect(timestamp).to be > after
          result = [ledger, timestamp]
          true
        end
        result
      end

      before(:suite) do
        services.start
        services.wait_for_vpsadmin_api
        services.unlock_transaction_signing_key(passphrase: 'test')
        node.start
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
      end

      describe 'boot auto-start obligations', order: :defined do
        it 'captures each boot inventory asynchronously and retains missed starts' do
          initial, initial_success = wait_for_boot_check(node, ids: [])
          expect(initial.fetch('captured_at_boottime_seconds')).to be < 300

          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'autostart-monitoring',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          ids = %w[healthy blocked].map do |name|
            vps = create_vps(
              services,
              admin_user_id: admin_user_id,
              node_id: node1_id,
              hostname: "autostart-#{name}"
            )
            id = vps.fetch('id')
            wait_for_vps_on_node(services, vps_id: id, node_id: node1_id, running: true)
            id
          end
          healthy_id, blocked_id = ids
          autostart_count = services.mariadb_scalar(
            sql: "SELECT COUNT(*) FROM vpses WHERE id IN (#{ids.map { |id| Integer(id) }.join(', ')}) " \
                 'AND autostart_enable = 1'
          )
          expect(autostart_count).to eq('2')
          still_empty, = wait_for_boot_check(node, ids: [], after: initial_success)
          expect(still_empty).to eq(initial)
          previous_history = state_history(node)
          expect(previous_history.fetch('boot_id')).to eq(initial.fetch('boot_id'))
          ids.each do |id|
            expect(previous_history.fetch('events')).to include(
              include('pool' => 'tank', 'id' => id.to_s, 'state' => 'running')
            )
          end
          previous_running = state_history(node, ever_running: true)
          expect(previous_running.fetch('entries').map { |row| row.values_at('pool', 'id') }).to include(
            ['tank', healthy_id.to_s], ['tank', blocked_id.to_s]
          )

          hook_path = "/tank/hook/ct/#{blocked_id}/pre-start"
          node.succeeds(<<~CMD)
            install -d -m 700 #{Shellwords.escape(File.dirname(hook_path))}
            install -m 700 /dev/stdin #{Shellwords.escape(hook_path)} <<'HOOK'
            #!/bin/sh
            exit 1
            HOOK
          CMD
          node.succeeds('poweroff -f', timeout: 60)
          node.wait_for_shutdown(timeout: 120)
          node.start
          node.wait_for_boot
          node.wait_for_osctl_pool('tank')
          wait_for_running_nodectld(node)
          node.wait_for_osctl_container(healthy_id.to_s, state: 'running', timeout: 180)

          captured, = wait_for_boot_check(node, ids: ids, pending: [blocked_id])
          expect(captured.fetch('boot_id')).not_to eq(initial.fetch('boot_id'))
          expect(captured.fetch('captured_at_boottime_seconds')).to be < 300
          running = state_history(node, ever_running: true)
          expect(running.fetch('boot_id')).to eq(captured.fetch('boot_id'))
          expect(running.fetch('entries').map { |row| row.fetch('id') }).not_to include(blocked_id.to_s)

          # The entire successful run occurs while nodectld cannot observe it.
          node.succeeds('sv down nodectld', timeout: 60)
          node.wait_until_succeeds('sv status nodectld | grep -q ^down:', timeout: 60)
          node.fails('nodectl status', timeout: 30)
          node.succeeds("rm -f #{Shellwords.escape(hook_path)}")
          node.wait_until_succeeds(
            "test \"$(osctl ct show -H -o state #{Integer(blocked_id)})\" = running || " \
            "osctl ct start #{Integer(blocked_id)}",
            timeout: 180
          )
          node.wait_for_osctl_container(blocked_id.to_s, state: 'running', timeout: 180)
          node.succeeds(<<~CMD)
            install -m 700 /dev/stdin #{Shellwords.escape(hook_path)} <<'HOOK'
            #!/bin/sh
            exit 1
            HOOK
          CMD
          node.succeeds("osctl ct stop #{Integer(blocked_id)}", timeout: 180)
          node.wait_for_osctl_container(blocked_id.to_s, state: 'stopped', timeout: 120)
          expect(boot_autostart_ledger(node)).to eq(captured)
          running = state_history(node, ever_running: true)
          expect(running.fetch('entries').map { |row| row.fetch('id') }).to include(blocked_id.to_s)

          node.succeeds('sv up nodectld', timeout: 60)
          wait_for_running_nodectld(node)
          fulfilled, = wait_for_boot_check(node, ids: ids)
          expect(fulfilled.values_at('boot_id', 'captured_at_boottime_seconds')).to eq(
            captured.values_at('boot_id', 'captured_at_boottime_seconds')
          )
          node.wait_for_osctl_container(blocked_id.to_s, state: 'stopped', timeout: 120)
          node.succeeds("rm -f #{Shellwords.escape(hook_path)}")
          node.wait_until_succeeds(
            "test \"$(osctl ct show -H -o state #{Integer(blocked_id)})\" = running || " \
            "osctl ct start #{Integer(blocked_id)}",
            timeout: 180
          )
          node.wait_for_osctl_container(healthy_id.to_s, state: 'running', timeout: 180)
          node.wait_for_osctl_container(blocked_id.to_s, state: 'running', timeout: 180)
          before_restart = state_history(node)
          expect(state_history(node, ever_running: true)).to eq(running)
          node.succeeds('sv restart osctld', timeout: 180)
          node.wait_for_osctl_pool('tank')
          node.wait_for_osctl_container(healthy_id.to_s, state: 'running', timeout: 180)
          node.wait_for_osctl_container(blocked_id.to_s, state: 'running', timeout: 180)
          expect(state_history(node)).to eq(before_restart)
          expect(state_history(node, ever_running: true)).to eq(running)
          _, restart_ready = node.succeeds('date +%s', timeout: 30)
          resumed, = wait_for_boot_check(node, ids: ids, after: Integer(restart_ready.strip))
          expect(resumed).to eq(fulfilled)
        end
      end
    '';
  }
)
