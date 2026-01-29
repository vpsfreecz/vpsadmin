let
  base = import ./test.nix;

  roleIds = {
    node = 0;
    storage = 1;
    mailer = 2;
    dns_server = 3;
  };

  mkNode =
    {
      key,
      id,
      name,
      ipAddr,
      role ? "node",
      maxVps ? if role == "node" then 30 else 0,
      cpus ? 4,
      memoryMiB ? 8 * 1024,
      swapMiB ? 0,
    }:
    let
      roleId = builtins.getAttr role roleIds;
      hypervisorType =
        if role == "node" || role == "storage" then
          # Node.register! sets vpsadminos for node/storage
          1
        else
          null;
    in
    rec {
      inherit
        id
        name
        ipAddr
        role
        maxVps
        cpus
        memoryMiB
        swapMiB
        ;
      attrName = key;
      domain = "${name}.${base.location.domain}";
      seedRecord = {
        inherit id name;
        location_id = base.location.id;
        ip_addr = ipAddr;
        max_vps = maxVps;
        cpus = cpus;
        total_memory = memoryMiB;
        total_swap = swapMiB;
        role = roleId;
        hypervisor_type = hypervisorType;
      };
      portReservations = builtins.genList (i: {
        node_id = id;
        port = 10000 + i;
      }) 100;
    };

  predefinedNodes = {
    node1 = mkNode {
      key = "node1";
      id = 101;
      name = "vpsadmin-node1";
      ipAddr = "192.168.10.11";
    };

    node2 = mkNode {
      key = "node2";
      id = 102;
      name = "vpsadmin-node2";
      ipAddr = "192.168.10.12";
    };

    storage1 = mkNode {
      key = "storage1";
      id = 201;
      name = "vpsadmin-storage1";
      ipAddr = "192.168.10.21";
      role = "storage";
      cpus = 4;
      memoryMiB = 4 * 1024;
      swapMiB = 0;
    };

    storage2 = mkNode {
      key = "storage2";
      id = 202;
      name = "vpsadmin-storage2";
      ipAddr = "192.168.10.22";
      role = "storage";
      cpus = 4;
      memoryMiB = 4 * 1024;
      swapMiB = 0;
    };
  };

  mkClusterSeed =
    { nodeRefs }:
    let
      getNode =
        nodeKey:
        if builtins.hasAttr nodeKey predefinedNodes then
          builtins.getAttr nodeKey predefinedNodes
        else
          throw "Unknown predefined node '${nodeKey}'";

      selectedNodes = builtins.mapAttrs (
        machineName: nodeKey:
        (getNode nodeKey)
        // {
          attrName = machineName;
        }
      ) nodeRefs;

      nodeList = builtins.attrValues selectedNodes;
    in
    {
      inherit (base)
        adminUser
        transactionKey
        environment
        location
        ;

      nodes = selectedNodes;

      seed = [
        {
          model = "Node";
          records = map (n: n.seedRecord) nodeList;
        }
        {
          model = "PortReservation";
          records = builtins.concatLists (map (n: n.portReservations) nodeList);
        }
      ];
    }
    // selectedNodes;
in
{
  inherit predefinedNodes mkClusterSeed;
}
