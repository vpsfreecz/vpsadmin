{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    mapAttrs'
    concatMapStringsSep
    listToAttrs
    nameValuePair
    optionalAttrs
    removePrefix
    ;

  seed = import ../../../api/db/seeds/test.nix;
  adminUser = seed.adminUser;

  cfg = config.vpsadmin.test;

  rabbitmqcfg = pkgs.stdenvNoCC.mkDerivation {
    pname = "rabbitmqcfg";
    version = "1.0";

    src = ../../../tools/rabbitmqcfg.rb;

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/rabbitmqcfg
      chmod +x $out/bin/rabbitmqcfg

      patchShebangs $out/bin/rabbitmqcfg
    '';

    buildInputs = [ pkgs.ruby ];
  };

  creds = import ./vpsadmin-credentials.nix;

  dbName = creds.database.name;
  dbUsers = creds.database.users;
  rabbitmqVhost = creds.rabbitmq.vhost;
  rabbitmqUsers = creds.rabbitmq.users;
  rabbitNodeUser = rabbitmqUsers.node;
  redisPassword = creds.redis.password;
  testApiUrl = "http://api.vpsadmin.test";
  vpsadminctlWrapper = pkgs.writeShellScriptBin "vpsadminctl" ''
    exec ${pkgs.vpsadmin-client}/bin/vpsadminctl -u ${testApiUrl} "$@"
  '';

  mkSecretEntry =
    {
      path,
      password,
      mode ? "0444",
      user ? null,
      group ? null,
    }:
    nameValuePair (removePrefix "/etc/" path) (
      {
        text = password;
        mode = mode;
      }
      // optionalAttrs (user != null) { inherit user; }
      // optionalAttrs (group != null) { inherit group; }
    );

  secretFiles =
    let
      dbFiles = map (
        user:
        mkSecretEntry {
          path = user.passwordFile;
          password = user.password;
        }
      ) (builtins.attrValues dbUsers);

      rabbitFiles = map (
        user:
        mkSecretEntry {
          path = user.passwordFile;
          password = user.password;
        }
      ) (builtins.attrValues rabbitmqUsers);

      redisFiles = [
        (mkSecretEntry {
          path = creds.redis.passwordFile;
          password = redisPassword;
          mode = "0400";
          user = "redis";
          group = "redis";
        })
      ];
      haveapiClient = nameValuePair "haveapi-client.yml" {
        text = ''
          ---
          :servers:
          - :url: ${testApiUrl}
            :auth:
              :basic:
                :user: ${adminUser.login}
                :password: ${adminUser.password}
            :last_auth: :basic
        '';
        mode = "0400";
      };
    in
    dbFiles ++ rabbitFiles ++ redisFiles ++ [ haveapiClient ];

  dbApiUser = dbUsers.api;
  dbSupervisorUser = dbUsers.supervisor;

  rabbitAdminUser = rabbitmqUsers.admin;
  rabbitApiUser = rabbitmqUsers.api;
  rabbitSupervisorUser = rabbitmqUsers.supervisor;
  rabbitConsoleUser = rabbitmqUsers.console;

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
  socketNetwork = "${cfg.socketAddress}/24";
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

      seedFiles = mkOption {
        type = types.listOf types.str;
        default = [ "test.nix" ];
        description = "List of seed files applied when initializing the test database.";
      };

      rabbitmqNodeUsers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "RabbitMQ user names (node domain names) to create for nodes in the cluster.";
      };
    };
  };

  config = {
    networking = {
      hostName = "vpsadmin-services";
      firewall.enable = true;
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

    environment.etc = listToAttrs secretFiles;

    environment.systemPackages = with pkgs; [
      mariadb
      rabbitmqcfg
      redis
      vpsadminctlWrapper
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
        CREATE DATABASE IF NOT EXISTS ${dbName} CHARACTER SET utf8mb3 COLLATE utf8mb3_unicode_ci;

        ${concatMapStringsSep "\n\n" (user: ''
          CREATE USER IF NOT EXISTS '${user.user}'@'%' IDENTIFIED BY '${user.password}';
          CREATE USER IF NOT EXISTS '${user.user}'@'localhost' IDENTIFIED BY '${user.password}';

          ALTER USER '${user.user}'@'%' IDENTIFIED BY '${user.password}';
          ALTER USER '${user.user}'@'localhost' IDENTIFIED BY '${user.password}';

          GRANT ALL PRIVILEGES ON ${dbName}.* TO '${user.user}'@'%';
          GRANT ALL PRIVILEGES ON ${dbName}.* TO '${user.user}'@'localhost';
        '') (builtins.attrValues dbUsers)}

        FLUSH PRIVILEGES;
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
        virtualHost = rabbitmqVhost;
        allowedIPv4Ranges = {
          cluster = [ socketNetwork ];
          clients = [ socketNetwork ];
        };
        initialScript = pkgs.writeScript "rabbitmq-setup.sh" ''
          #!${pkgs.bash}/bin/bash

          cookieFile=/var/lib/rabbitmq/.erlang.cookie

          for _i in {1..120}; do
            [ -e "$cookieFile" ] && break
            echo "Waiting for cookie file at $cookieFile"
            sleep 1
          done

          if [ ! -e "$cookieFile" ]; then
            echo "Cookie file not found at $cookieFile"
          fi

          cp "$cookieFile" /root/

          set -e

          rabbitmqcfg=${rabbitmqcfg}/bin/rabbitmqcfg

          $rabbitmqcfg setup --vhost ${rabbitmqVhost} --execute ${rabbitAdminUser.user}:${rabbitAdminUser.password}

          $rabbitmqcfg user --vhost ${rabbitmqVhost} --create --perms --execute api ${rabbitApiUser.user}:${rabbitApiUser.password}
          $rabbitmqcfg user --vhost ${rabbitmqVhost} --create --perms --execute console ${rabbitConsoleUser.user}:${rabbitConsoleUser.password}
          $rabbitmqcfg user --vhost ${rabbitmqVhost} --create --perms --execute supervisor ${rabbitSupervisorUser.user}:${rabbitSupervisorUser.password}
          ${lib.optionalString (cfg.rabbitmqNodeUsers != [ ]) ''
            for node_user in ${lib.concatStringsSep " " cfg.rabbitmqNodeUsers}; do
              $rabbitmqcfg user --vhost ${rabbitmqVhost} --create --perms --execute node ${"$"}{node_user}:${rabbitNodeUser.password}
            done
          ''}

          $rabbitmqcfg policies --vhost ${rabbitmqVhost} --execute
        '';
      };

      redis = {
        enable = true;
        passwordFile = creds.redis.passwordFile;
      };

      database = {
        enable = true;
        allowedIPv4Ranges = [ socketNetwork ];
      };

      databaseSetup = {
        database = {
          name = dbName;
          user = dbApiUser.user;
          passwordFile = dbApiUser.passwordFile;
          host = "127.0.0.1";
          port = 3306;
        };
        autoSetup = true;
        createLocally = true;
        seedFiles = cfg.seedFiles;
      };

      api = {
        enable = true;
        database = {
          name = dbName;
          user = dbApiUser.user;
          passwordFile = dbApiUser.passwordFile;
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
          name = dbName;
          user = dbSupervisorUser.user;
          passwordFile = dbSupervisorUser.passwordFile;
          host = "127.0.0.1";
          port = 3306;
        };
        rabbitmq = {
          username = rabbitSupervisorUser.user;
          passwordFile = rabbitSupervisorUser.passwordFile;
        };
        servers = 1;
      };

      console-router = {
        enable = true;
        address = "127.0.0.1";
        rabbitmq = {
          username = rabbitConsoleUser.user;
          passwordFile = rabbitConsoleUser.passwordFile;
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
              host = "127.0.0.1";
              port = 9292;
            }
          ];
        };

        console-router.test = {
          frontend.bind = [ "unix@/run/haproxy/vpsadmin-console-router.sock mode 0666" ];
          backends = [
            {
              host = "127.0.0.1";
              port = 8000;
            }
          ];
        };

        webui.test = {
          frontend.bind = [ "unix@/run/haproxy/vpsadmin-webui.sock mode 0666" ];
          backends = [
            {
              host = "127.0.0.1";
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
