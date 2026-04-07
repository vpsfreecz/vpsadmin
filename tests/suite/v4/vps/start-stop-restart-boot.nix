import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ../storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };
  in
  {
    name = "vps-start-stop-restart-boot";

    description = ''
      Exercise the runtime VPS lifecycle on a single node: start, stop,
      restart, and rescue boot.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      def action_state_id(output)
        output.dig('_meta', 'action_state_id') || output.dig('response', '_meta', 'action_state_id')
      end

      def vps_action(services, args:, parameters: {})
        _, output = services.vpsadminctl.succeeds(args: args, parameters: parameters)
        { 'chain_id' => action_state_id(output) }
      end

      def expect_vps_chain_done(services, response, label:, expected_handles: [])
        final_state = wait_for_vps_chain_done(services, response.fetch('chain_id'))
        handles = chain_transactions(services, response.fetch('chain_id')).map { |row| row.fetch('handle') }
        audit = {
          chain_id: response.fetch('chain_id'),
          final_state: final_state,
          handles: handles,
          failure_details: chain_failure_details(services, response.fetch('chain_id'))
        }

        expect(final_state).to eq(services.class::CHAIN_STATES[:done]), "#{label}: #{audit.inspect}"

        expected_handles.each do |handle|
          expect(handles).to include(handle), "#{label}: #{audit.inspect}"
        end

        audit
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'lifecycle actions', order: :defined do
        it 'runs start, stop, restart, and rescue boot end to end' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-lifecycle',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-lifecycle'
          )

          start_response = vps_action(services, args: ['vps', 'start', vps.fetch('id').to_s])
          expect_vps_chain_done(
            services,
            start_response,
            label: 'start',
            expected_handles: [tx_types(services).fetch('vps_start')]
          )
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          stop_response = vps_action(services, args: ['vps', 'stop', vps.fetch('id').to_s])
          expect_vps_chain_done(
            services,
            stop_response,
            label: 'stop',
            expected_handles: [tx_types(services).fetch('vps_stop')]
          )
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: false)

          restart_response = vps_action(services, args: ['vps', 'restart', vps.fetch('id').to_s])
          expect_vps_chain_done(
            services,
            restart_response,
            label: 'restart',
            expected_handles: [tx_types(services).fetch('vps_restart')]
          )
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          boot_response = vps_boot(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            mount_root_dataset: '/mnt/rootfs'
          )
          expect_vps_chain_done(
            services,
            boot_response,
            label: 'boot',
            expected_handles: [tx_types(services).fetch('vps_boot')]
          )
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          motd = nil
          wait_until_block_succeeds(name: "rescue boot for VPS #{vps.fetch('id')} is visible inside the container") do
            _, motd = vps_exec(
              node,
              vps_id: vps.fetch('id'),
              command: 'cat /etc/motd',
              timeout: 120
            )

            motd.include?('VPS in rescue mode!') && motd.include?('/mnt/rootfs')
          end

          expect(motd).to include('VPS in rescue mode!')
          expect(motd).to include('/mnt/rootfs')
        end
      end
    '';
  }
)
