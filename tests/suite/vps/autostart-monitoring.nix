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
      Reboot a node with two auto-start VPSes and verify that nodectld reports
      the VPS whose pre-start hook prevents it from running.
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

      def metric_line(name, labels: nil, value: 1.0)
        label_text = labels ? "{#{labels.map { |key, val| "#{key}=\"#{val}\"" }.join(',')}}" : nil
        "#{name}#{label_text} #{value}"
      end

      def wait_for_metric(node, line, present:, timeout: 180)
        wait_until_block_succeeds(
          name: "metric #{line.inspect} present=#{present}",
          timeout: timeout
        ) do
          _, output = node.succeeds('cat /run/metrics/nodectld.prom', timeout: 30)

          if present
            expect(output.lines.map(&:strip)).to include(line)
          else
            expect(output.lines.map(&:strip)).not_to include(line)
          end

          true
        end
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'VPS auto-start reconciliation', order: :defined do
        it 'reports the VPS that fails to start and clears it after recovery' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'autostart-monitoring',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          healthy_vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'autostart-healthy'
          )
          blocked_vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'autostart-blocked'
          )
          healthy_id = healthy_vps.fetch('id')
          blocked_id = blocked_vps.fetch('id')

          wait_for_vps_on_node(
            services,
            vps_id: healthy_id,
            node_id: node1_id,
            running: true
          )
          wait_for_vps_on_node(
            services,
            vps_id: blocked_id,
            node_id: node1_id,
            running: true
          )
          autostart_count = services.mariadb_scalar(
            sql: "SELECT COUNT(*) FROM vpses " \
                 "WHERE id IN (#{Integer(healthy_id)}, #{Integer(blocked_id)}) " \
                 'AND autostart_enable = 1'
          )
          expect(autostart_count).to eq('2')

          hook_path = "/tank/hook/ct/#{blocked_id}/pre-start"
          node.succeeds(<<~CMD)
            install -d -m 700 #{Shellwords.escape(File.dirname(hook_path))}
            install -m 700 /dev/stdin #{Shellwords.escape(hook_path)} <<'EOF'
            #!/bin/sh
            exit 1
            EOF
          CMD

          node.succeeds('poweroff -f', timeout: 60)
          node.wait_for_shutdown(timeout: 120)
          node.start
          node.wait_for_boot
          node.wait_for_osctl_pool('tank')
          wait_for_running_nodectld(node)

          wait_for_osctl_container_runtime(
            node,
            healthy_id.to_s,
            runtime_state: 'running',
            timeout: 180
          )

          check_success = metric_line(
            'nodectld_vps_autostart_check_success'
          )
          expected = metric_line(
            'nodectld_vps_autostart_expected',
            labels: { pool: 'tank' },
            value: 2.0
          )
          blocked = metric_line(
            'nodectld_vps_autostart_unsatisfied',
            labels: { pool: 'tank', vps_id: blocked_id }
          )
          healthy = metric_line(
            'nodectld_vps_autostart_unsatisfied',
            labels: { pool: 'tank', vps_id: healthy_id }
          )

          wait_for_metric(node, check_success, present: true)
          wait_for_metric(node, expected, present: true)
          wait_for_metric(node, blocked, present: true)
          wait_for_metric(node, healthy, present: false)
          _, metrics = node.succeeds(
            'cat /run/metrics/nodectld.prom',
            timeout: 30
          )
          expect(metrics).to match(
            /^nodectld_vps_autostart_unsatisfied_reason\{pool="tank",vps_id="#{blocked_id}",reason="[^"]+"\} 1\.0$/
          )

          node.succeeds("rm -f #{Shellwords.escape(hook_path)}")
          ensure_osctl_container_running(
            node,
            blocked_id,
            timeout: 180
          )
          wait_for_osctl_container_runtime(
            node,
            blocked_id.to_s,
            runtime_state: 'running',
            timeout: 180
          )

          wait_for_metric(node, blocked, present: false)
          wait_for_metric(node, expected, present: true)
          wait_for_metric(node, check_success, present: true)

          node.succeeds('poweroff -f', timeout: 120)
          node.wait_for_shutdown(timeout: 120)
        end
      end
    '';
  }
)
