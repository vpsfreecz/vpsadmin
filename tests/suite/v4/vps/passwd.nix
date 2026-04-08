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
    name = "vps-passwd";

    description = ''
      Reset the root password of a running VPS, verify the hash changes inside
      the guest, and confirm the transaction input is sanitized afterwards.
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

      describe 'standalone password reset', order: :defined do
        it 'changes the root password hash and clears the saved transaction input' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-passwd',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-passwd'
          )

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          _, before_hash = vps_exec(
            node,
            vps_id: vps.fetch('id'),
            command: "grep '^root:' /etc/shadow | cut -d: -f2",
            timeout: 120
          )

          response = vps_passwd(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            type: 'secure'
          )
          audit, = expect_chain_done(
            services,
            response,
            label: 'standalone-passwd',
            expected_handles: [tx_types(services).fetch('vps_passwd')]
          )

          after_hash = nil
          wait_until_block_succeeds(name: "root password changed on VPS #{vps.fetch('id')}") do
            _, after_hash = vps_exec(
              node,
              vps_id: vps.fetch('id'),
              command: "grep '^root:' /etc/shadow | cut -d: -f2",
              timeout: 120
            )

            after_hash.strip != before_hash.strip
          end

          saved_input = services.mysql_scalar(sql: <<~SQL)
            SELECT input
            FROM transactions
            WHERE transaction_chain_id = #{Integer(response.fetch('chain_id'))}
              AND handle = #{Integer(tx_types(services).fetch('vps_passwd'))}
            ORDER BY id
            LIMIT 1
          SQL

          expect(response.fetch('password').to_s).not_to eq(""), audit.inspect
          expect(after_hash.strip).not_to eq(before_hash.strip), audit.inspect
          expect(saved_input.to_s).not_to include(response.fetch('password')), audit.inspect
        end
      end
    '';
  }
)
