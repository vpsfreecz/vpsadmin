{ config, pkgs, lib, ... }:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.console-router;

  bundle = "${cfg.package}/ruby-env/bin/bundle";

  databaseYml = pkgs.writeText "database.yml" ''
    production:
      adapter: mysql2
      database: ${cfg.database.name}
      host: ${cfg.database.host}
      port: ${toString cfg.database.port}
      username: ${cfg.database.user}
      password: #dbpass#
      ${optionalString (cfg.database.socket != null) "socket: ${cfg.database.socket}"}
  '';

  serverWait = 15;

  thinYml = pkgs.writeText "thin.yml" ''
    address: ${cfg.address}
    port: ${toString cfg.port}
    rackup: ${cfg.package}/console_router/config.ru
    pid: ${cfg.stateDirectory}/pids/thin.pid
    log: ${cfg.stateDirectory}/log/thin.log
    environment: production
    wait: ${toString serverWait}
    tag: console-router
  '';
in {
  options = {
    vpsadmin.console-router = {
      enable = mkEnableOption "Enable vpsAdmin console router server";

      package = mkOption {
        type = types.package;
        default = pkgs.vpsadmin-console-router;
        description = "Which vpsAdmin consoel router package to use.";
        example = "pkgs.vpsadmin-console-router.override { ruby = pkgs.ruby_3_1; }";
      };

      user = mkOption {
        type = types.str;
        default = "vpsadmin-console";
        description = "User under which the console router is ran.";
      };

      group = mkOption {
        type = types.str;
        default = "vpsadmin-console";
        description = "Group under which the console router is ran.";
      };

      address = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address on which the console router is ran.";
      };

      port = mkOption {
        type = types.int;
        default = 8000;
        description = "Port on which the console router is ran.";
      };

      stateDirectory = mkOption {
        type = types.str;
        default = "${vpsadminCfg.stateDirectory}/console_router";
        description = "The state directory";
      };

      allowedIPv4Ranges = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          List of IPv4 ranges to be allowed access to the server within the firewall
        '';
      };

      allowedIPv6Ranges = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          List of IPv6 ranges to be allowed access to the server within the firewall
        '';
      };

      database = {
        host = mkOption {
          type = types.str;
          default = "localhost";
          description = "Database host address.";
        };

        port = mkOption {
          type = types.int;
          default = 3306;
          defaultText = "3306";
          description = "Database host port.";
        };

        name = mkOption {
          type = types.str;
          default = "vpsadmin";
          description = "Database name.";
        };

        user = mkOption {
          type = types.str;
          default = "vpsadmin-console";
          description = "Database user.";
        };

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = "/run/keys/vpsadmin-console-dbpassword";
          description = ''
            A file containing the password corresponding to
            <option>database.user</option>.
          '';
        };

        socket = mkOption {
          type = types.nullOr types.path;
          default =
            if cfg.database.isLocal then
              "/run/mysqld/mysqld.sock"
            else
             null;
          defaultText = "/run/mysqld/mysqld.sock";
          example = "/run/mysqld/mysqld.sock";
          description = "Path to the unix socket file to use for authentication.";
        };

        isLocal = mkOption {
          type = types.bool;
          default = false;
          description = "Set if the database is on localhost.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    vpsadmin = {
      enableOverlay = true;
      enableStateDirectory = true;
    };

    networking.firewall.extraCommands = concatStringsSep "\n" (
      (map (ip: ''
        iptables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString cfg.port} -j nixos-fw-accept
      '') cfg.allowedIPv4Ranges)
      ++
      (map (ip: ''
        ip6tables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString cfg.port} -j nixos-fw-accept
      '') cfg.allowedIPv6Ranges)
    );

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDirectory}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/config' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/log' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/pids' 0750 ${cfg.user} ${cfg.group} - -"

      "d /run/vpsadmin/console_router - - - - -"
      "L+ /run/vpsadmin/console_router/config - - - - ${cfg.stateDirectory}/config"
    ];

    systemd.services.vpsadmin-console-router = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      preStart = ''
        # Handle database.passwordFile & permissions
        DBPASS=${optionalString (cfg.database.passwordFile != null) "$(head -n1 ${cfg.database.passwordFile})"}
        cp -f ${databaseYml} "${cfg.stateDirectory}/config/database.yml"
        sed -e "s,#dbpass#,$DBPASS,g" -i "${cfg.stateDirectory}/config/database.yml"
        chmod 440 "${cfg.stateDirectory}/config/database.yml"
      '';

      serviceConfig =
        let
          thin = "${bundle} exec thin --config ${thinYml}";
        in {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          TimeoutSec = "300";
          WorkingDirectory = "${cfg.package}/console_router";
          ExecStart="${thin} start";
          Restart = "on-failure";
          RestartSec = 30;
        };
    };

    users.users = optionalAttrs (cfg.user == "vpsadmin-console") {
      ${cfg.user} = {
        group = cfg.group;
        home = cfg.stateDirectory;
        isSystemUser = true;
      };
    };

    users.groups = optionalAttrs (cfg.group == "vpsadmin-console") {
      ${cfg.group} = {};
    };
  };
}
