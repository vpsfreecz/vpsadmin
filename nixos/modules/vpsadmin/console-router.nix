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
    pid: ${cfg.stateDir}/pids/thin.pid
    log: ${cfg.stateDir}/log/thin.log
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
        example = "pkgs.vpsadmin-console-router.override { ruby = pkgs.ruby_2_7; }";
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

      stateDir = mkOption {
        type = types.str;
        default = "${vpsadminCfg.stateDir}/console_router";
        description = "The state directory";
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
      enableStateDir = true;
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/config' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/log' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/pids' 0750 ${cfg.user} ${cfg.group} - -"

      "d /run/vpsadmin/console_router - - - - -"
      "L+ /run/vpsadmin/console_router/config - - - - ${cfg.stateDir}/config"
    ];

    systemd.services.vpsadmin-console-router = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      preStart = ''
        # Handle database.passwordFile & permissions
        DBPASS=${optionalString (cfg.database.passwordFile != null) "$(head -n1 ${cfg.database.passwordFile})"}
        cp -f ${databaseYml} "${cfg.stateDir}/config/database.yml"
        sed -e "s,#dbpass#,$DBPASS,g" -i "${cfg.stateDir}/config/database.yml"
        chmod 440 "${cfg.stateDir}/config/database.yml"
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
        };
    };

    users.users = optionalAttrs (cfg.user == "vpsadmin-console") {
      ${cfg.user} = {
        group = cfg.group;
        home = cfg.stateDir;
        isSystemUser = true;
      };
    };

    users.groups = optionalAttrs (cfg.group == "vpsadmin-console") {
      ${cfg.group} = {};
    };
  };
}
