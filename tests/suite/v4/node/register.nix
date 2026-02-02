import ../../../make-test.nix (
  { pkgs, ... }:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    creds = import ../../../configs/nixos/vpsadmin-credentials.nix;

    rabbitmqVhost = creds.rabbitmq.vhost;
    rabbitmqUsers = creds.rabbitmq.users;
    rabbitNodeUser = rabbitmqUsers.node;

    socket = {
      services = "192.168.10.10";
      node = "192.168.10.11";
    };

    location = seed.location;

    nodeSpec = rec {
      id = 101;
      name = "vpsadmin-node";
      domainName = "${name}.${location.domain}";
      cpus = 4;
      memoryMiB = 8 * 1024;
      swapMiB = 0;
      maxVps = 30;
    };
  in
  {
    name = "node-register";

    description = ''
      Bring up a single-node vpsAdmin cluster: a NixOS VM with all services and
      a vpsAdminOS node connected over a socket network. Register the node via
      vpsadminctl and wait for nodectld to report a running status.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "node"
    ];

    machines = {
      services = {
        spin = "nixos";
        tags = [ "vpsadmin-services" ];
        networks = [
          { type = "user"; }
          { type = "socket"; }
        ];
        config = {
          imports = [
            ../../../configs/nixos/vpsadmin-services.nix
          ];

          vpsadmin.test = {
            socketAddress = socket.services;
            socketPeers = {
              "${nodeSpec.name}" = socket.node;
            };
          };
        };
      };

      node = {
        disks = [
          {
            type = "file";
            device = "{machine}-tank.img";
            size = "20G";
          }
        ];

        networks = [
          { type = "user"; }
          { type = "socket"; }
        ];

        config = {
          imports = [
            <vpsadminos/tests/configs/vpsadminos/base.nix>
            <vpsadminos/tests/configs/vpsadminos/pool-tank.nix>
            ../../../configs/vpsadminos/node.nix
          ];

          boot.qemu.memory = 8192;
          boot.qemu.cpus = 4;

          vpsadmin.test.node = {
            socketAddress = socket.node;
            servicesAddress = socket.services;
            nodeId = nodeSpec.id;
            nodeName = nodeSpec.name;
            locationDomain = location.domain;
            socketPeers = {
              vpsadmin-services = socket.services;
            };
          };
        };
      };
    };

    testScript = ''
      require 'json'

      location_id = ${toString location.id}

      def register_node(services, node_id:, name:, location_id:, ip_addr:, cpus:, mem_mib:, swap_mib:, max_vps:)
        # TODO: this command fails on timeout, because it takes a long time to create node port reservations
        services.vpsadminctl.execute(
          args: %w[node create],
          parameters: {
            id: node_id,
            name: name,
            type: 'node',
            hypervisor_type: 'vpsadminos',
            location: location_id,
            ip_addr: ip_addr,
            cpus: cpus,
            total_memory: mem_mib,
            total_swap: swap_mib,
            max_vps: max_vps
          }
        )
      end

      def expect_running_nodectld(node)
        node.wait_for_service('nodectld')
        wait_until_block_succeeds(name: 'nodectld running') do
          _, output = node.succeeds('nodectl status', timeout: 180)
          expect(output).to include('State: running')
          true
        end
      end

      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        [services, node].each(&:start)
      end

      describe 'node' do
        it 'boots and imports pool' do
          node.wait_for_zpool('tank')
          node.wait_for_osctl_pool('tank')
        end

        it 'reaches services over socket network' do
          node.wait_until_succeeds("ping -c 1 ${socket.services}", timeout: 60)
          services.wait_until_succeeds("ping -c 1 ${socket.node}", timeout: 60)
        end
      end

      describe 'registration' do
        it 'waits for the api server' do
          services.vpsadminctl.wait_until_succeeds(args: %w[cluster public_stats])
        end

        it 'creates rabbitmq user' do
          services.wait_for_service('vpsadmin-rabbitmq-setup.service')
          services.succeeds("rabbitmqcfg user --vhost ${rabbitmqVhost} --create --perms --execute node ${nodeSpec.domainName}:${rabbitNodeUser.password}")
        end

        it 'registers node and starts nodectld' do
          register_node(
            services,
            node_id: ${toString nodeSpec.id},
            name: "${nodeSpec.name}",
            location_id: location_id,
            ip_addr: "${socket.node}",
            cpus: ${toString nodeSpec.cpus},
            mem_mib: ${toString nodeSpec.memoryMiB},
            swap_mib: ${toString nodeSpec.swapMiB},
            max_vps: ${toString nodeSpec.maxVps}
          )

          sleep(120)

          services.succeeds('systemctl restart vpsadmin-supervisor.service')
          services.wait_for_service('vpsadmin-supervisor.service')

          node.succeeds('sv restart nodectld')
          expect_running_nodectld(node)
        end
      end
    '';
  }
)
