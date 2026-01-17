{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkDefault
    mkMerge
    mkOption
    types
    mapAttrs'
    ;

  cfg = config.vpsadmin.test;

  secretsDir = "/etc/vpsadmin-test";
  dbUser = "vpsadmin";
  dbPassword = "vpsadmin";
  dbPassFile = "${secretsDir}/db-password";

  rabbitUser = "vpsadmin";
  rabbitPassword = "vpsadmin";
  rabbitPassFile = "${secretsDir}/rabbitmq-password";

  redisPassword = "vpsadmin";
  redisPassFile = "${secretsDir}/redis-password";

  varnishPort = 6081;

  socketPeersAsHosts = mapAttrs' (host: addr: lib.nameValuePair addr [ host ]) cfg.socketPeers;
in
{
  options.vpsadmin.test = {
    socketAddress = mkOption {
      type = types.str;
      default = "192.168.10.10";
      description = "IPv4 address on the socket network for the services VM.";
    };

    socketPeers = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Mapping of hostnames to socket-network IPv4 addresses for peer VMs.";
    };
  };

  imports = [
    ../../../nixos/modules/nixos-modules.nix
  ];

  config = mkMerge [
    {
      networking = {
        hostName = "vpsadmin-services";
        firewall.enable = false;
        interfaces.eth1.useDHCP = false;
        interfaces.eth1.ipv4.addresses = [
          {
            address = cfg.socketAddress;
            prefixLength = 24;
          }
        ];
        hosts = {
          "127.0.0.1" = [
            "api.vpsadmin.test"
            "console.vpsadmin.test"
            "webui.vpsadmin.test"
            "varnish.vpsadmin.test"
          ];
          "${cfg.socketAddress}" = [ "vpsadmin-services" ];
        }
        // socketPeersAsHosts;
      };

      environment.etc = {
        "vpsadmin-test/db-password".text = dbPassword;
        "vpsadmin-test/db-password".mode = "0444";

        "vpsadmin-test/rabbitmq-password".text = rabbitPassword;
        "vpsadmin-test/rabbitmq-password".mode = "0444";

        "vpsadmin-test/redis-password".text = redisPassword;
        "vpsadmin-test/redis-password".mode = "0400";
        "vpsadmin-test/redis-password".user = "redis";
        "vpsadmin-test/redis-password".group = "redis";
      };

      environment.systemPackages = with pkgs; [
        mariadb
        redis
      ];

      virtualisation = {
        memorySize = 8192;
        cores = 8;
      };

      services.mysql = {
        enable = true;
        settings.mysqld = {
          bind_address = "0.0.0.0";
          max_connections = 200;
        };
        initialScript = pkgs.writeText "vpsadmin-test-mysql-init.sql" ''
          CREATE DATABASE IF NOT EXISTS vpsadmin CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci;

          CREATE USER IF NOT EXISTS '${dbUser}'@'%' IDENTIFIED BY '${dbPassword}';
          CREATE USER IF NOT EXISTS '${dbUser}'@'localhost' IDENTIFIED BY '${dbPassword}';

          ALTER USER '${dbUser}'@'%' IDENTIFIED BY '${dbPassword}';
          ALTER USER '${dbUser}'@'localhost' IDENTIFIED BY '${dbPassword}';

          GRANT ALL PRIVILEGES ON vpsadmin.* TO '${dbUser}'@'%';
          GRANT ALL PRIVILEGES ON vpsadmin.* TO '${dbUser}'@'localhost';

          FLUSH PRIVILEGES;
        '';
      };

      services.rabbitmq = {
        # Ensure a predictable user/password for the test environment
        config = ''
          [
            {rabbit, [
              {default_user, <<"${rabbitUser}">>},
              {default_pass, <<"${rabbitPassword}">>},
              {loopback_users, []}
            ]}
          ].
        '';
      };

    }

    {
      vpsadmin = {
        enableStateDirectory = true;

        rabbitmq = {
          enable = true;
          hosts = [ "127.0.0.1" ];
          virtualHost = "/";
        };

        redis = {
          enable = true;
          passwordFile = redisPassFile;
        };

        database = {
          enable = true;
        };

        databaseSetup = {
          database = {
            user = dbUser;
            passwordFile = dbPassFile;
            host = "127.0.0.1";
            port = 3306;
          };
          autoSetup = true;
          createLocally = true;
          seedFiles = [
            "test"
          ];
        };

        api = {
          enable = true;
          database = {
            user = dbUser;
            passwordFile = dbPassFile;
            host = "127.0.0.1";
            port = 3306;
          };
          rake.enableDefaultTasks = true;
          scheduler.enable = true;
          threads.min = 1;
          threads.max = 8;
          workers = 2;
          address = "0.0.0.0";
        };

        supervisor = {
          enable = true;
          database = {
            user = dbUser;
            passwordFile = dbPassFile;
            host = "127.0.0.1";
            port = 3306;
          };
          rabbitmq = {
            username = rabbitUser;
            passwordFile = rabbitPassFile;
          };
          servers = 1;
        };

        console-router = {
          enable = true;
          address = "0.0.0.0";
          rabbitmq = {
            username = rabbitUser;
            passwordFile = rabbitPassFile;
          };
        };

        varnish = {
          enable = true;
          bind = {
            address = "127.0.0.1";
            port = varnishPort;
          };
          api.default = {
            domain = "varnish.vpsadmin.test";
            backend = {
              host = "127.0.0.1";
              port = config.vpsadmin.api.port;
            };
          };
        };

        frontend = {
          enable = true;
          enableACME = false;
          forceSSL = false;
          api.default = {
            domain = "api.vpsadmin.test";
            backend = {
              host = "127.0.0.1";
              port = varnishPort;
            };
          };
          console-router.default = {
            domain = "console.vpsadmin.test";
            backend = {
              host = "127.0.0.1";
              port = config.vpsadmin.console-router.port;
            };
          };
        };

        webui = {
          enable = true;
          domain = "webui.vpsadmin.test";
          api.externalUrl = "http://api.vpsadmin.test";
          api.internalUrl = "http://api.vpsadmin.test";
          productionEnvironmentId = 1;
          usernsPublic = false;
          exportPublic = false;
          nasPublic = false;
          errorReporting = "E_ALL";
        };

        waitOnline.api = {
          enable = true;
          url = "http://127.0.0.1:${toString config.vpsadmin.api.port}/";
        };
      };
    }
  ];
}
