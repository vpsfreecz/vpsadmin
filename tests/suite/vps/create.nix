import ../../make-test.nix (
  { pkgs, ... }:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    location = seed.location;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeId = clusterSeed.node.id;
  in
  {
    name = "vps-create";

    description = ''
      Boot a single-node vpsAdmin cluster from the shared machine definition and
      wait for the API to become reachable.
    '';

    tags = [
      "vpsadmin"
      "vps"
    ];

    machines = import ../../machines/cluster/1-node.nix pkgs;

    testScript = ''
      configure_examples do |config|
        config.default_order = :defined
      end

      auth_opts = "-u http://api.vpsadmin.test --auth basic --user \"${adminUser.login}\" --password \"${adminUser.password}\""
      location_id = ${toString location.id}
      user_id = ${toString adminUser.id}
      node_id = ${toString nodeId}
      os_template_id = 1
      pool_label = "tank"
      pool_fs = "tank/ct"
      pool_role = "hypervisor"
      max_datasets = 100
      cpu = 1
      memory = 1024
      swap = 0
      diskspace = 10240
      ipv4 = 0
      ipv4_private = 0
      ipv6 = 0

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        node.wait_for_service('nodectld')
        node.wait_until_succeeds("nodectl status | grep 'State: running'", timeout: 180)
      end

      describe 'cluster', order: :defined do
        it 'responds to API requests' do
          services.wait_for_vpsadmin_api(timeout: 300)
        end

        it 'creates storage pool' do
          services.succeeds(
            "vpsadminctl #{auth_opts} pool create -- " \
            "--node #{node_id} --label #{pool_label} --filesystem #{pool_fs} " \
            "--role #{pool_role} --is-open --max-datasets #{max_datasets} " \
            "--refquota-check"
          )
        end

        it 'creates a VPS' do
          _, output = services.succeeds(
            "vpsadminctl #{auth_opts} -H --columns -o id vps new -- " \
            "--user #{user_id} --node #{node_id} " \
            "--os-template #{os_template_id} " \
            "--hostname vps-test --cpu #{cpu} --memory #{memory} --swap #{swap} " \
            "--diskspace #{diskspace} --ipv4 #{ipv4} --ipv4-private #{ipv4_private} --ipv6 #{ipv6}"
          )

          @vps_id = output.strip.to_i
        end

        it 'starts a VPS' do
          services.succeeds("vpsadminctl #{auth_opts} vps start #{@vps_id}")
          services.wait_until_succeeds("vpsadminctl #{auth_opts} vps show #{@vps_id} | grep 'Running:' | grep 'true'")
        end
      end
    '';
  }
)
