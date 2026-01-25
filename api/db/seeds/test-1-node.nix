let
  base = import ./test.nix;

  node = rec {
    id = 101;
    name = "vpsadmin-node";
    domain = "${name}.${base.location.domain}";
    ipAddr = "192.168.10.11";
    cpus = 4;
    memoryMiB = 8 * 1024;
    swapMiB = 0;
    maxVps = 30;
  };

  portReservations = builtins.genList (i: {
    node_id = node.id;
    port = 10000 + i;
  }) 100;
in
{
  inherit (base)
    adminUser
    transactionKey
    environment
    location
    ;

  inherit node;

  seed = [
    {
      model = "Node";
      records = [
        {
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
        }
      ];
    }
    {
      model = "PortReservation";
      records = portReservations;
    }
  ];
}
