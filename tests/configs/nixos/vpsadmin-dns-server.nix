{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mapAttrs'
    mkOption
    nameValuePair
    types
    ;

  creds = import ./vpsadmin-credentials.nix;
  seed = import ../../../api/db/seeds/test.nix;
  txKey = seed.transactionKey;

  cfg = config.vpsadmin.test.dnsServer;

  dbUser = creds.database.users.nodectld;
  rabbitUser = creds.rabbitmq.users.node;

  socketPeersAsHosts = mapAttrs' (host: addr: nameValuePair addr [ host ]) cfg.socketPeers;
in
{
  imports = [
    ../../../nixos/modules/nixos-modules.nix
  ];

  options.vpsadmin.test.dnsServer = {
    socketAddress = mkOption {
      type = types.str;
      default = "192.168.10.31";
      description = "IPv4 address on the socket network for the DNS server.";
    };

    servicesAddress = mkOption {
      type = types.str;
      default = "192.168.10.10";
      description = "Socket-network IPv4 address of the services VM.";
    };

    socketPeers = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Mapping of hostnames to socket-network IPv4 addresses.";
    };

    nodeId = mkOption {
      type = types.int;
      default = 301;
      description = "Node id of the DNS server in vpsAdmin.";
    };

    nodeName = mkOption {
      type = types.str;
      default = "vpsadmin-dns1";
      description = "Hostname to use for the DNS server.";
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
      firewall.enable = true;
      resolvconf.useLocalResolver = false;

      interfaces.eth1 = {
        useDHCP = false;
        ipv4.addresses = [
          {
            address = cfg.socketAddress;
            prefixLength = 24;
          }
        ];
      };

      firewall.interfaces.eth1 = {
        allowedTCPPorts = [ 53 ];
        allowedUDPPorts = [ 53 ];
      };

      hosts = {
        "${cfg.socketAddress}" = [
          cfg.nodeName
          "${cfg.nodeName}.${cfg.locationDomain}"
        ];
        "${cfg.servicesAddress}" = [
          "api.vpsadmin.test"
          "vpsadmin-services"
        ];
      }
      // socketPeersAsHosts;
    };

    virtualisation = {
      memorySize = 2048;
      cores = 2;
    };

    environment.etc."vpsadmin/transaction.key".text = cfg.transactionPublicKey;

    systemd.tmpfiles.rules = [
      "d /var/named 0755 named named -"
      "d /var/named/vpsadmin 0755 named named -"
      "d /var/named/vpsadmin/db 0755 named named -"
      "d /var/named/vpsadmin/primary_type 0755 named named -"
      "d /var/named/vpsadmin/secondary_type 0755 named named -"
      "f /var/named/vpsadmin/named.conf 0644 named named -"
    ];

    services.bind = {
      enable = true;
      directory = "/var/named";
      ipv4Only = true;
      listenOn = [ cfg.socketAddress ];
      listenOnIpv6 = [ ];
      forwarders = [ ];
      cacheNetworks = [ ];
      configFile = pkgs.writeText "vpsadmin-test-named.conf" ''
        include "/etc/bind/rndc.key";

        controls {
          inet 127.0.0.1 port 953 allow { 127.0.0.1; } keys { "rndc-key"; };
        };

        options {
          directory "/var/named";
          pid-file "/run/named/named.pid";
          session-keyfile "/run/named/session.key";
          listen-on port 53 { ${cfg.socketAddress}; };
          listen-on-v6 { none; };
          allow-query { any; };
          recursion no;
          dnssec-validation no;
        };

        statistics-channels {
          inet 127.0.0.1 port 8053 allow { 127.0.0.1; };
        };

        include "/var/named/vpsadmin/named.conf";
      '';
    };

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
            type = "dns_server";
          };
        };
      };
    };
  };
}
