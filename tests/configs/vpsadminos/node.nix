{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    optionals
    mkOption
    nameValuePair
    types
    mapAttrs'
    ;

  creds = import ../nixos/vpsadmin-credentials.nix;
  seed = import ../../../api/db/seeds/test.nix;
  txKey = seed.transactionKey;

  cfg = config.vpsadmin.test.node;
  isV5 = config.vpsadmin.nodectld.version == "5";

  dbUser = creds.database.users.nodectld;
  rabbitUser = creds.rabbitmq.users.node;

  socketPeersAsHosts = mapAttrs' (host: addr: nameValuePair addr [ host ]) cfg.socketPeers;
in
{
  imports = [
    ../../../nixos/modules/vpsadminos-modules.nix
  ];

  options.vpsadmin.test.node = {
    socketAddress = mkOption {
      type = types.str;
      default = "192.168.10.11";
      description = "IPv4 address on the socket network for the vpsadminos node.";
    };

    servicesAddress = mkOption {
      type = types.str;
      default = "192.168.10.10";
      description = "Socket-network IPv4 address of the services VM.";
    };

    socketPeers = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Mapping of hostnames to socket-network IPv4 addresses for peer VMs.";
    };

    nodeId = mkOption {
      type = types.int;
      default = 101;
      description = "Node id used when registering with vpsAdmin.";
    };

    nodeName = mkOption {
      type = types.str;
      default = "vpsadmin-node";
      description = "Hostname to use for the vpsadminos node.";
    };

    locationDomain = mkOption {
      type = types.str;
      description = "Location domain.";
    };

    transactionPublicKey = mkOption {
      type = types.str;
      default = txKey.public;
      description = "Public key used to verify signed transactions from vpsAdmin.";
    };
  };

  config = {
    networking = {
      hostName = cfg.nodeName;
      hosts = {
        "${cfg.socketAddress}" = [ cfg.nodeName ];
        "${cfg.servicesAddress}" = [
          "api.vpsadmin.test"
          "console.vpsadmin.test"
          "download.vpsadmin.test"
          "webui.vpsadmin.test"
          "varnish.vpsadmin.test"
          "vpsadmin-services"
        ];
      }
      // socketPeersAsHosts;
      custom = ''
        ip addr add ${cfg.socketAddress}/24 dev eth1
        ip link set eth1 up
      '';
      firewall.interfaces.eth1.allowedTCPPortRanges = [
        {
          from = 10000;
          to = 20000;
        }
      ];
      firewall.interfaces.eth1.allowedTCPPorts = optionals isV5 [ 8082 ];
    };

    osctl.exportfs.enable = true;

    services.prometheus.exporters.osctl.enable = true;

    environment.etc."vpsadmin/transaction.key".text = cfg.transactionPublicKey;

    vpsadmin = {
      rabbitmq = {
        hosts = [ cfg.servicesAddress ];
        virtualHost = creds.rabbitmq.vhost;
      };

      nodectld = {
        enable = true;

        settings = {
          db = {
            hosts = [ cfg.servicesAddress ];
            user = dbUser.user;
            pass = dbUser.password;
            name = creds.database.name;
          };

          rabbitmq = {
            username = "${cfg.nodeName}.${cfg.locationDomain}";
            password = rabbitUser.password;
          };

          vpsadmin = {
            node_id = cfg.nodeId;
            node_name = "${cfg.nodeName}.${cfg.locationDomain}";
            node_addr = cfg.socketAddress;
            net_interfaces = [ "eth1" ];
            transaction_public_key = "/etc/vpsadmin/transaction.key";
          };

          vnc = {
            port = 8082;
          };
        };
      };

      console-server.enable = isV5;
    };
  };
}
