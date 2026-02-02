{
  seedPath,
  seed ? import seedPath,
  nodes,
  servicesSocket ? "192.168.10.10",
  bootMemory ? 8192,
  bootCpus ? 4,
}:
_pkgs:
let
  nodeEntries = builtins.mapAttrs (
    machineName: node:
    node
    // {
      attrName = machineName;
      domainName = if node ? domain then node.domain else "${node.name}.${seed.location.domain}";
    }
  ) nodes;

  nodeList = builtins.attrValues nodeEntries;

  servicesPeers = builtins.listToAttrs (
    map (node: {
      name = node.name;
      value = node.ipAddr;
    }) nodeList
  );

  rabbitmqNodeUsers = map (node: node.domainName) nodeList;

  seedFiles = [
    "test.nix"
    (builtins.baseNameOf seedPath)
  ];

  mkNodeSocketPeers =
    nodeSpec:
    builtins.listToAttrs (
      [
        {
          name = "vpsadmin-services";
          value = servicesSocket;
        }
      ]
      ++ map (peer: {
        name = peer.name;
        value = peer.ipAddr;
      }) (builtins.filter (peer: peer.attrName != nodeSpec.attrName) nodeList)
    );

  mkNodeMachine = machineName: nodeSpec: {
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

      boot.qemu.memory = bootMemory;
      boot.qemu.cpus = bootCpus;

      vpsadmin.test.node = {
        socketAddress = nodeSpec.ipAddr;
        servicesAddress = servicesSocket;
        nodeId = nodeSpec.id;
        nodeName = nodeSpec.name;
        locationDomain = seed.location.domain;
        socketPeers = mkNodeSocketPeers nodeSpec;
      };

      vpsadmin.nodectld.version = nodeSpec.nodectlVersion;
    };
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
        ../../../configs/nixos/vpsadmin-services.nix
      ];

      vpsadmin.test = {
        socketAddress = servicesSocket;
        socketPeers = servicesPeers;
        seedFiles = seedFiles;
        rabbitmqNodeUsers = rabbitmqNodeUsers;
      };
    };
  };
}
// builtins.mapAttrs mkNodeMachine nodeEntries
