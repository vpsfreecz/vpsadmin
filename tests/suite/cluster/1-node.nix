import ../../make-test.nix (
  { pkgs, ... }:
  {
    name = "cluster-1-node";

    description = ''
      Boot the reusable single-node vpsAdmin cluster and verify API availability
      plus running nodectld on the node.
    '';

    tags = [
      "vpsadmin"
      "cluster"
      "node"
    ];

    machines = import ../../machines/cluster/1-node.nix pkgs;

    testScript = ''
      before(:suite) do
        [services, node].each(&:start)
      end

      describe 'cluster' do
        it 'services API responds' do
          services.wait_for_vpsadmin_api
        end

        it 'nodectld is running' do
          node.wait_for_service('nodectld')
          node.wait_until_succeeds("nodectl status | grep 'State: running'", timeout: 180)
        end
      end
    '';
  }
)
