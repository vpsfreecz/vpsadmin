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
        wait_until_block_succeeds(name: 'nodectld running') do
          _, output = node.succeeds('nodectl status', timeout: 180)
          expect(output).to include('State: running')
          true
        end
      end

      describe 'cluster', order: :defined do
        it 'responds to API requests' do
          services.wait_for_vpsadmin_api(timeout: 300)
        end

        it 'creates storage pool' do
          services.vpsadminctl.succeeds(
            args: %w[pool create],
            parameters: {
              node: node_id,
              label: pool_label,
              filesystem: pool_fs,
              role: pool_role,
              is_open: true,
              max_datasets: max_datasets,
              refquota_check: true
            }
          )
        end

        it 'creates a VPS' do
          _, output = services.vpsadminctl.succeeds(
            args: %w[vps new],
            parameters: {
              user: user_id,
              node: node_id,
              os_template: os_template_id,
              hostname: 'vps-test',
              cpu: cpu,
              memory: memory,
              swap: swap,
              diskspace: diskspace,
              ipv4: ipv4,
              ipv4_private: ipv4_private,
              ipv6: ipv6
            }
          )

          @vps_id = output.fetch('vps').fetch('id')
        end

        it 'starts a VPS' do
          services.vpsadminctl.succeeds(args: ['vps', 'start', @vps_id.to_s])

          wait_for_block(name: 'VPS to start') do
            _, output = services.vpsadminctl.succeeds(args: ['vps', 'show', @vps_id])
            output.fetch('vps').fetch('is_running')
          end
        end
      end
    '';
  }
)
