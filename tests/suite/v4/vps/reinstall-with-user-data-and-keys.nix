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
    name = "vps-reinstall-with-user-data-and-keys";

    description = ''
      Reinstall a running VPS with auto-add SSH keys and VPS user data, then
      verify the key and user-data side effects inside the container.
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

      def expect_vps_chain_done(services, response, label:, expected_handles: [])
        final_state = wait_for_vps_chain_done(services, response.fetch('chain_id'))
        transactions = chain_transactions(services, response.fetch('chain_id'))
        handles = transactions.map { |row| row.fetch('handle') }
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

        [audit, transactions]
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'reinstall with user data and keys', order: :defined do
        it 'redeploys auto-add keys and executes script user data after reinstall' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-reinstall-user-data',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-reinstall-user-data'
          )

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          public_key = deploy_user_public_key(
            services,
            admin_user_id: admin_user_id,
            user_id: admin_user_id,
            label: 'Reinstall Auto Key',
            key: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIreinstallintegration reinstall@test',
            auto_add: true
          )
          user_data = create_vps_user_data(
            services,
            admin_user_id: admin_user_id,
            user_id: admin_user_id,
            label: 'Reinstall Script',
            format: 'script',
            content: <<~SCRIPT
              #!/bin/sh
              printf 'user-data-ran\n' > /root/reinstall-user-data.txt
            SCRIPT
          )

          response = vps_reinstall(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            user_data_id: user_data.fetch('id')
          )
          _audit, transactions = expect_vps_chain_done(
            services,
            response,
            label: 'reinstall-with-user-data-and-keys',
            expected_handles: [
              tx_types(services).fetch('vps_reinstall'),
              tx_types(services).fetch('vps_deploy_public_key'),
              tx_types(services).fetch('vps_deploy_user_data'),
              tx_types(services).fetch('vps_start')
            ]
          )

          start_tx = transactions.find do |row|
            row.fetch('handle') == tx_types(services).fetch('vps_start')
          end

          expect(start_tx).not_to be_nil
          expect(start_tx.fetch('reversible')).to eq(2)

          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          authorized_keys = nil
          user_data_output = nil

          wait_until_block_succeeds(name: "reinstalled VPS #{vps.fetch('id')} has key and user-data effect") do
            authorized_keys = vps_authorized_keys_lines(node, vps_id: vps.fetch('id'), timeout: 120)
            _, user_data_output = vps_exec(
              node,
              vps_id: vps.fetch('id'),
              command: 'cat /root/reinstall-user-data.txt',
              timeout: 120
            )

            authorized_keys.include?(public_key.fetch('key')) && user_data_output.include?('user-data-ran')
          end

          expect(authorized_keys).to include(public_key.fetch('key'))
          expect(user_data_output).to include('user-data-ran')
        end
      end
    '';
  }
)
