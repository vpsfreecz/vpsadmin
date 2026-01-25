_pkgs:
let
  seed = import ../../../api/db/seeds/test-1-node.nix;

  location = seed.location;

  socket = {
    services = "192.168.10.10";
    node = seed.node.ipAddr;
  };

  nodeSpec = {
    inherit (seed.node)
      id
      name
      ipAddr
      maxVps
      cpus
      memoryMiB
      swapMiB
      ;
    domainName = seed.node.domain;
  };
in
{
  services = {
    spin = "nixos";
    tags = [ "vpsadmin-services" ];
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
        seedFiles = [
          "test.nix"
          "test-1-node.nix"
        ];
        rabbitmqNodeUsers = [ nodeSpec.domainName ];
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
}
