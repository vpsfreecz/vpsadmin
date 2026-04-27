let
  base = import ./test.nix;

  dnsNode = rec {
    id = 301;
    name = "vpsadmin-dns1";
    domain = "${name}.${base.location.domain}";
    ipAddr = "192.168.10.31";
    maxVps = 0;
    cpus = 1;
    memoryMiB = 1024;
    swapMiB = 0;
    role = 3; # Node.roles[:dns_server]
  };
in
{
  inherit dnsNode;

  seed = [
    {
      model = "Node";
      records = [
        {
          id = dnsNode.id;
          name = dnsNode.name;
          location_id = base.location.id;
          ip_addr = dnsNode.ipAddr;
          max_vps = dnsNode.maxVps;
          cpus = dnsNode.cpus;
          total_memory = dnsNode.memoryMiB;
          total_swap = dnsNode.swapMiB;
          role = dnsNode.role;
          hypervisor_type = null;
        }
      ];
    }
  ];
}
