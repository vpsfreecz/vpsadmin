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
    name = "admin-nodectl-refresh-and-runtime-state";

    description = ''
      Verify that nodectl refresh drives runtime publication and DB updates.
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

      describe 'nodectl refresh and runtime state', order: :defined do
        it 'refreshes node status and keeps read-only RPCs healthy' do
          initial_row = nil

          wait_until_block_succeeds(name: "initial node status row for node #{node1_id}") do
            initial_row = node_current_status_row(services, node_id: node1_id)
            !initial_row.nil?
          end

          initial_time = Integer(initial_row.fetch('time'))
          sleep 1

          node.succeeds('nodectl refresh', timeout: 120)

          wait_until_block_succeeds(name: "node status time advances after refresh") do
            row = node_current_status_row(services, node_id: node1_id)
            row && Integer(row.fetch('time')) > initial_time
          end

          status_response = nodectl_remote_json(node, command: :status)
          expect(status_response.fetch('status')).to eq('ok')
          expect(status_response.fetch('response').fetch('state').fetch('run')).to eq(true)

          accounting_response = nodectl_remote_json(
            node,
            command: :get,
            params: { resource: 'net_accounting' }
          )
          expect(accounting_response.fetch('status')).to eq('ok')
          expect(accounting_response.fetch('response').fetch('interfaces')).to be_a(Array)
        end
      end
    '';
  }
)
