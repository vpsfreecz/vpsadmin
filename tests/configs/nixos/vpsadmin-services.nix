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
  dbPassword = "testDatabasePassword";
  dbPassFile = "${secretsDir}/db-password";

  rabbitUser = "vpsadmin";
  rabbitPassword = "testRabbitPassword";
  rabbitPassFile = "${secretsDir}/rabbitmq-password";

  redisPassword = "testRedisPassword";
  redisPassFile = "${secretsDir}/redis-password";

  socketPeersAsHosts = mapAttrs' (host: addr: lib.nameValuePair addr [ host ]) cfg.socketPeers;

  plugins = [
    "monitoring"
    "newslog"
    "outage_reports"
    "payments"
    "requests"
    "webui"
  ];

  webuiPort = 8134;
in
{
  imports = [
    ../../../nixos/modules/nixos-modules.nix
  ];

  options = {
    vpsadmin.test = {
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
  };

  config = {
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
          "download.vpsadmin.test"
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

    systemd.tmpfiles.rules = [
      "d /run/varnish 0755 varnish varnish -"
    ];

    # webui must be nested inside a container, because it is using nginx same
    # as frontend, but we wish to test the proxy setup and haproxy integration
    containers.webui = {
      autoStart = true;
      privateNetwork = false;
      config =
        { config, lib, ... }:
        {
          imports = [
            ../../../nixos/modules/nixos-modules.nix
          ];

          time.timeZone = "UTC";

          services.nginx.defaultListen = [
            {
              addr = "127.0.0.1";
              port = webuiPort;
            }
          ];

          vpsadmin = {
            inherit plugins;

            webui = {
              enable = true;
              domain = "webui.vpsadmin.test";
              api.externalUrl = "http://api.vpsadmin.test";
              api.internalUrl = "http://api.vpsadmin.test";
              productionEnvironmentId = 1;
              usernsPublic = true;
              exportPublic = true;
              nasPublic = true;
              errorReporting = "E_ALL";
            };
          };

          system.stateVersion = lib.trivial.release;
        };
    };

    vpsadmin = {
      enableStateDirectory = true;

      inherit plugins;

      rabbitmq = {
        enable = true;
        hosts = [ "127.0.0.1" ];
        virtualHost = "vpsadmin_test";
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

      download-mounter = {
        enable = false;
        api.url = "http://api.vpsadmin.test";
        api.tokenFile = "/private/vpsadmin-api.token";
        mountpoint = "/mnt/download";
      };

      haproxy = {
        enable = true;

        api.test = {
          frontend.bind = [ "unix@/run/haproxy/vpsadmin-api.sock mode 0666" ];
          backends = [
            {
              host = "localhost";
              port = 9292;
            }
          ];
        };

        console-router.test = {
          frontend.bind = [ "unix@/run/haproxy/vpsadmin-console-router.sock mode 0666" ];
          backends = [
            {
              host = "localhost";
              port = 8000;
            }
          ];
        };

        webui.test = {
          frontend.bind = [ "unix@/run/haproxy/vpsadmin-webui.sock mode 0666" ];
          backends = [
            {
              host = "localhost";
              port = webuiPort;
            }
          ];
        };
      };

      varnish = {
        enable = true;

        bind = {
          address = "/run/varnish/vpsadmin-varnish.sock";
          mode = "0666";
        };

        api.test = {
          domain = "api.vpsadmin.test";
          backend.path = "/run/haproxy/vpsadmin-api.sock";
        };
      };

      frontend = {
        enable = true;
        enableACME = false;
        forceSSL = false;

        api.test = {
          domain = "api.vpsadmin.test";
          backend = {
            address = "unix:/run/varnish/vpsadmin-varnish.sock";
          };
        };

        console-router.test = {
          domain = "console.vpsadmin.test";
          backend = {
            address = "unix:/run/haproxy/vpsadmin-console-router.sock";
          };
        };

        # download-mounter.test = {
        #   domain = "download.vpsadmin.test";
        # };

        webui.test = {
          domain = "webui.vpsadmin.test";
          backend = {
            address = "unix:/run/haproxy/vpsadmin-webui.sock";
          };
        };
      };

      waitOnline.api = {
        enable = true;
        url = "http://127.0.0.1:${toString config.vpsadmin.api.port}/";
      };
    };
  };
}
