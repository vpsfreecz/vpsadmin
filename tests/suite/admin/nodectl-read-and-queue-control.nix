import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
    };
  in
  {
    name = "admin-nodectl-read-and-queue-control";

    description = ''
      Exercise safe nodectl read commands and queue pause/resume control on a
      real node.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "admin"
    ];

    machines = import ../../machines/cluster/1-node.nix args;

    testScript = common + ''
      before(:suite) do
        setup_admin_cluster(services, node)
      end

      describe 'nodectl read and queue control', order: :defined do
        it 'reads runtime state and controls the VPS queue' do
          node.succeeds('nodectl resume', timeout: 60)

          _, ping = node.succeeds('nodectl ping', timeout: 60)
          expect(ping).to include('pong')

          _, status = node.succeeds('nodectl status', timeout: 60)
          expect(status).to include('State: running')
          expect(status).to include('Queues:')

          config_response = nodectl_remote_json(
            node,
            command: :get,
            params: { resource: 'config' }
          )
          expect(config_response.fetch('status')).to eq('ok')
          expect(config_response.fetch('response').fetch('config')).to have_key('vpsadmin')

          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'admin-nodectl-read',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'admin-nodectl-read'
          )
          wait_for_vps_on_node(
            services,
            vps_id: vps.fetch('id'),
            node_id: node1_id,
            running: true
          )

          wait_until_block_succeeds(name: "veth map includes VPS #{vps.fetch('id')}") do
            veth_response = nodectl_remote_json(
              node,
              command: :get,
              params: { resource: 'veth_map' }
            )
            map = veth_response.fetch('response').fetch('veth_map')
            map.fetch(vps.fetch('id').to_s).any?
          end

          begin
            node.succeeds('nodectl queue pause vps', timeout: 60)
            stop_response = services.api_ruby_json(code: <<~RUBY)
              #{api_session_prelude(admin_user_id)}

              vps = Vps.find(#{Integer(vps.fetch('id'))})
              chain, = TransactionChains::Vps::Stop.fire(vps)

              puts JSON.dump(chain_id: chain.id)
            RUBY
            chain_id = stop_response.fetch('chain_id')

            wait_until_block_succeeds(name: "VPS stop chain #{chain_id} is queued") do
              queue_response = nodectl_remote_json(
                node,
                command: :get,
                params: { resource: 'queue', limit: 100 }
              )
              queued = queue_response.fetch('response').fetch('queue')

              queued.any? do |row|
                Integer(row.fetch('chain')) == Integer(chain_id) &&
                  Integer(row.fetch('vps_id')) == Integer(vps.fetch('id'))
              end
            end

            node.succeeds('nodectl queue resume vps', timeout: 60)

            final_state = wait_for_vps_chain_done(services, chain_id)
            expect(final_state).to eq(services.class::CHAIN_STATES[:done])
            wait_for_vps_on_node(
              services,
              vps_id: vps.fetch('id'),
              node_id: node1_id,
              running: false
            )
          ensure
            node.succeeds('nodectl queue resume all', timeout: 60)
          end
        end
      end
    '';
  }
)
