{ ... }:
let
  seed = import ../../../api/db/seeds/test.nix;
  dnsSeed = import ../../../api/db/seeds/test-dns-server-node.nix;
  dnsNode = dnsSeed.dnsNode;
  servicesSocket = "192.168.10.10";
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
        socketAddress = servicesSocket;
        socketPeers = {
          ${dnsNode.name} = dnsNode.ipAddr;
        };
        seedFiles = [
          "test.nix"
          "test-dns-server-node.nix"
        ];
        rabbitmqNodeUsers = [ dnsNode.domain ];
      };
    };
  };

  dns = {
    spin = "nixos";
    networks = [
      { type = "user"; }
      { type = "socket"; }
    ];
    config = {
      imports = [
        ../../configs/nixos/vpsadmin-dns-server.nix
      ];

      vpsadmin.test.dnsServer = {
        socketAddress = dnsNode.ipAddr;
        servicesAddress = servicesSocket;
        nodeId = dnsNode.id;
        nodeName = dnsNode.name;
        locationDomain = seed.location.domain;
        socketPeers = {
          vpsadmin-services = servicesSocket;
        };
      };
    };
  };
}
