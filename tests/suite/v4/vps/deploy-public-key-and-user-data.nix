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
    name = "vps-deploy-public-key-and-user-data";

    description = ''
      Deploy a standalone public SSH key and standalone script user data to a
      running VPS and verify both are present in the guest rootfs.
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

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'standalone key and user-data deployment', order: :defined do
        it 'deploys the key once and writes the script payload into the guest rootfs' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-standalone-deploy',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-standalone-deploy'
          )

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          public_key = deploy_user_public_key(
            services,
            admin_user_id: admin_user_id,
            user_id: admin_user_id,
            label: 'Standalone Deploy Key',
            key: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFphase2standalone phase2-standalone@test'
          )
          key_response = vps_deploy_public_key(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            public_key_id: public_key.fetch('id')
          )
          key_audit, = expect_chain_done(
            services,
            key_response,
            label: 'standalone-public-key',
            expected_handles: [tx_types(services).fetch('vps_deploy_public_key')]
          )

          authorized_keys = nil
          wait_until_block_succeeds(name: "public key deployed to VPS #{vps.fetch('id')}") do
            authorized_keys = vps_authorized_keys_lines(node, vps_id: vps.fetch('id'), timeout: 120)
            authorized_keys.count(public_key.fetch('key')) == 1
          end

          expect(authorized_keys.count(public_key.fetch('key'))).to eq(1), key_audit.inspect

          user_data = create_vps_user_data(
            services,
            admin_user_id: admin_user_id,
            user_id: admin_user_id,
            label: 'Standalone Deploy Script',
            format: 'script',
            content: <<~SCRIPT
              #!/bin/sh
              printf 'deploy-user-data-sentinel\n' > /root/deploy-user-data-sentinel.txt
            SCRIPT
          )
          user_data_response = vps_deploy_user_data(
            services,
            admin_user_id: admin_user_id,
            vps_user_data_id: user_data.fetch('id'),
            vps_id: vps.fetch('id')
          )
          user_data_audit, = expect_chain_done(
            services,
            user_data_response,
            label: 'standalone-user-data',
            expected_handles: [tx_types(services).fetch('vps_deploy_user_data')]
          )

          wrapper = nil
          script = nil
          wait_until_block_succeeds(name: "user data deployed to VPS #{vps.fetch('id')}") do
            _, wrapper = vps_exec(
              node,
              vps_id: vps.fetch('id'),
              command: 'cat /usr/local/vpsadmin-script/wrapper.sh',
              timeout: 120
            )
            _, script = vps_exec(
              node,
              vps_id: vps.fetch('id'),
              command: 'cat /usr/local/vpsadmin-script/user-script',
              timeout: 120
            )

            wrapper.include?('/usr/local/vpsadmin-script/user-script') &&
              script.include?('deploy-user-data-sentinel')
          end

          expect(wrapper).to include('/usr/local/vpsadmin-script/user-script'), user_data_audit.inspect
          expect(script).to include('deploy-user-data-sentinel'), user_data_audit.inspect
        end
      end
    '';
  }
)
