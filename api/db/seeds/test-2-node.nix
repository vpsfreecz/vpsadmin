let
  base = import ./test.nix;

  mkNode =
    {
      id,
      name,
      ipAddr,
    }:
    {
      inherit id name ipAddr;
      domain = "${name}.${base.location.domain}";
      cpus = 4;
      memoryMiB = 8 * 1024;
      swapMiB = 0;
      maxVps = 30;
    };

  node1 = mkNode {
    id = 101;
    name = "vpsadmin-node1";
    ipAddr = "192.168.10.11";
  };

  node2 = mkNode {
    id = 102;
    name = "vpsadmin-node2";
    ipAddr = "192.168.10.12";
  };

  nodes = [
    node1
    node2
  ];

  mkPortReservations =
    node:
    builtins.genList (i: {
      node_id = node.id;
      port = 10000 + i;
    }) 100;

  portReservations = builtins.concatLists (map mkPortReservations nodes);
in
{
  inherit (base)
    adminUser
    transactionKey
    environment
    location
    ;

  inherit node1 node2 nodes;

  seed = [
    {
      model = "Node";
      records = map (node: {
        id = node.id;
        name = node.name;
        location_id = base.location.id;
        ip_addr = node.ipAddr;
        max_vps = node.maxVps;
        cpus = node.cpus;
        total_memory = node.memoryMiB;
        total_swap = node.swapMiB;
        role = 0;
        hypervisor_type = 1;
      }) nodes;
    }
    {
      model = "PortReservation";
      records = portReservations;
    }
  ];
}
