import ../../../make-test.nix (
  { pkgs, vpsadminosPath, ... }:
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
            (vpsadminosPath + "/tests/configs/vpsadminos/pool-tank.nix")
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
        _, output = services.vpsadminctl.execute(
          args: %w[node create],
          opts: {
            block: false
          },
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

        output
      end

      def expect_running_nodectld(node)
        node.wait_for_service('nodectld')
        wait_until_block_succeeds(name: 'nodectld running') do
          _, output = node.succeeds('nodectl status', timeout: 180)
          expect(output).to include('State: running')
          true
        end
      end

      def wait_for_registration_chain_id(services, node_id)
        chain_id = nil

        wait_until_block_succeeds(name: "registration chain for node #{node_id}") do
          chain_id = services.mysql_scalar(sql: <<~SQL)
            SELECT c.transaction_chain_id
            FROM transaction_chain_concerns c
            INNER JOIN transaction_chains ch ON ch.id = c.transaction_chain_id
            WHERE c.class_name = 'Node'
              AND c.row_id = #{Integer(node_id)}
              AND ch.name = 'register'
            ORDER BY c.transaction_chain_id DESC
            LIMIT 1
          SQL

          chain_id && !chain_id.empty?
        end

        Integer(chain_id)
      end

      def node_row(services, node_id)
        services.mysql_json_rows(sql: <<~SQL).first
          SELECT JSON_OBJECT(
            'id', id,
            'name', name,
            'active', active,
            'role', role,
            'hypervisor_type', hypervisor_type,
            'ip_addr', ip_addr
          )
          FROM nodes
          WHERE id = #{Integer(node_id)}
          LIMIT 1
        SQL
      end

      def node_port_reservation_count(services, node_id)
        services.mysql_json_rows(sql: <<~SQL).first.fetch('count')
          SELECT JSON_OBJECT('count', COUNT(*))
          FROM port_reservations
          WHERE node_id = #{Integer(node_id)}
        SQL
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
          @registration_chain_id = wait_for_registration_chain_id(services, ${toString nodeSpec.id})

          sleep(120)

          services.succeeds('systemctl restart vpsadmin-supervisor.service')
          services.wait_for_service('vpsadmin-supervisor.service')

          node.succeeds('sv restart nodectld')
          expect_running_nodectld(node)
          services.wait_for_chain_state(@registration_chain_id, state: :done, timeout: 300)
          row = node_row(services, ${toString nodeSpec.id})

          expect(row.fetch('name')).to eq("${nodeSpec.name}")
          expect(row.fetch('ip_addr')).to eq("${socket.node}")
          expect(row.fetch('active')).to eq(1)
          expect(row.fetch('role')).to eq(0)
          expect(row.fetch('hypervisor_type')).to eq(1)
          expect(node_port_reservation_count(services, ${toString nodeSpec.id})).to eq(10_000)
          expect(services.mysql_scalar(sql: <<~SQL).to_i).to eq(0)
            SELECT COUNT(*)
            FROM resource_locks
            WHERE locked_by_type = 'TransactionChain'
              AND locked_by_id = #{@registration_chain_id}
          SQL
        end
      end
    '';
  }
)
