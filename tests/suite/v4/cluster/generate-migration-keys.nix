import ../../../make-test.nix (
  { ... }@args:
  let
    seed = import ../../../../api/db/seeds/test-2-node.nix;
    common = import ../storage/remote-common.nix {
      adminUserId = seed.adminUser.id;
      node1Id = seed.nodes.node1.id;
      node2Id = seed.nodes.node2.id;
      manageCluster = false;
    };
  in
  {
    name = "cluster-generate-migration-keys";
    description = ''
      Generate migration send keys for eligible pools across two nodes and
      verify that the public keys are stored both on the nodes and in the API
      database.
    '';

    machines = import ../../../machines/v4/cluster/2-node.nix args;
    tags = [
      "ci"
      "vpsadmin"
      "cluster"
      "pool"
    ];

    testScript = common + ''
      require 'shellwords'

      def node_send_public_key(machine, pool_name:)
        escaped_pool = Shellwords.escape(pool_name)
        _, path = machine.succeeds("osctl --pool #{escaped_pool} send key path public")
        _, key = machine.succeeds("cat #{Shellwords.escape(path.strip)}")
        key.strip
      end

      before(:suite) do
        [services, node1, node2].each(&:start)
        services.wait_for_vpsadmin_api
        [node1, node2].each { |n| wait_for_running_nodectld(n) }
        wait_for_node_ready(services, node1_id)
        wait_for_node_ready(services, node2_id)
      end

      describe 'cluster generate_migration_keys' do
        it 'generates send keys on eligible pools and persists public keys' do
          pool1 = create_pool(
            services,
            node_id: node1_id,
            label: 'migration-node1',
            filesystem: 'tank/migration-node1',
            role: 'primary'
          )
          pool2 = create_pool(
            services,
            node_id: node2_id,
            label: 'migration-node2',
            filesystem: 'tank/migration-node2',
            role: 'primary'
          )

          wait_for_pool_online(services, pool1.fetch('id'))
          wait_for_pool_online(services, pool2.fetch('id'))
          set_pool_migration_public_key(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool1.fetch('id'),
            public_key: nil
          )
          set_pool_migration_public_key(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool2.fetch('id'),
            public_key: nil
          )

          _, output = generate_migration_keys(services)
          chain_id = action_state_id(output)
          services.wait_for_chain_state(chain_id, state: :done) if chain_id

          node1_key = node_send_public_key(node1, pool_name: pool1.fetch('filesystem').split('/').first)
          node2_key = node_send_public_key(node2, pool_name: pool2.fetch('filesystem').split('/').first)

          expect(pool_migration_public_key(services, pool1.fetch('id'))).to eq(node1_key)
          expect(pool_migration_public_key(services, pool2.fetch('id'))).to eq(node2_key)
          expect(node1_key).to start_with('ssh-ed25519 ')
          expect(node2_key).to start_with('ssh-ed25519 ')
        end
      end
    '';
  }
)
