import ../../make-test.nix (
  { pkgs, ... }:
  let
    creds = import ../../configs/nixos/vpsadmin-credentials.nix;
    adminUser = builtins.fromJSON (builtins.readFile ../../../api/db/seeds/test/admin-user.json);

    rabbitmqVhost = creds.rabbitmq.vhost;
    rabbitmqUsers = creds.rabbitmq.users;
    rabbitNodeUser = rabbitmqUsers.node;

    socket = {
      services = "192.168.10.10";
      node = "192.168.10.11";
    };

    location = {
      label = "test-location";
      domain = "lab";
      description = "Test location for node registration";
      environment = 1;
      remoteConsoleServer = "http://console.vpsadmin.test";
    };

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
      "vpsadmin"
      "node"
    ];

    machines = {
      services = {
        spin = "nixos";
        networks = [
          { type = "user"; }
          { type = "socket"; }
        ];
        config = {
          imports = [
            ../../configs/nixos/vpsadmin-services.nix
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
            ../../configs/vpsadminos/node.nix
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

      api_url = "http://api.vpsadmin.test"
      auth_opts = "-u #{api_url} --auth basic --user \"${adminUser.login}\" --password \"${adminUser.password}\""

      location_label = "${location.label}"

      def register_location(services, auth_opts, label, domain, description, env, console_server)
        _, output = services.succeeds(
          "vpsadminctl #{auth_opts} -H --columns -o id location create -- " \
          "--label #{label} --domain #{domain} --description '#{description}' --environment #{env} --remote-console-server '#{console_server}' --has-ipv6 false"
        )
        output.strip.to_i
      end

      def register_node(services, auth_opts, node_id:, name:, location_id:, ip_addr:, cpus:, mem_mib:, swap_mib:, max_vps:)
        # TODO: this command fails on timeout, because it takes a long time to create node port reservations
        services.execute(
          "vpsadminctl #{auth_opts} node create -- " \
          "--id #{node_id} --name #{name} --type node --hypervisor-type vpsadminos " \
          "--location #{location_id} --ip-addr #{ip_addr} " \
          "--cpus #{cpus} --total-memory #{mem_mib} --total-swap #{swap_mib} --max-vps #{max_vps}"
        )
      end

      def expect_running_nodectld(node)
        node.wait_for_service('nodectld')
        node.wait_until_succeeds("nodectl status | grep 'State: running'", timeout: 180)
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
          # TODO: The client needs authentication even for actions that do not required it
          services.wait_until_succeeds("vpsadminctl -u http://api.vpsadmin.test/ --auth basic --user nouser --password nopassword cluster public_stats")
        end

        it 'creates rabbitmq user' do
          services.wait_for_service('vpsadmin-rabbitmq-setup.service')
          services.succeeds("rabbitmqcfg user --vhost ${rabbitmqVhost} --create --perms --execute node ${nodeSpec.domainName}:${rabbitNodeUser.password}")
        end

        it 'registers location and node, then starts nodectld' do
          location_id = register_location(
            services, auth_opts, location_label,
            "${location.domain}", "${location.description}", ${toString location.environment}, "${location.remoteConsoleServer}"
          )

          register_node(
            services,
            auth_opts,
            node_id: ${toString nodeSpec.id},
            name: "${nodeSpec.name}",
            location_id:,
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
