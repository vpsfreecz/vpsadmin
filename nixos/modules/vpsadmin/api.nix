{ config, pkgs, lib, ... }:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.api;

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

  serverWait = 90;

  thinYml = pkgs.writeText "thin.yml" ''
    address: ${cfg.address}
    port: ${toString cfg.port}
    servers: ${toString cfg.servers}
    rackup: ${cfg.package}/api/config.ru
    pid: ${cfg.stateDir}/pids/thin.pid
    log: ${cfg.stateDir}/log/thin.log
    daemonize: true
    onebyone: true
    environment: production
    wait: ${toString serverWait}
    tag: api
  '';
in {
  options = {
    vpsadmin.api = {
      enable = mkEnableOption "Enable vpsAdmin API server";

      package = mkOption {
        type = types.package;
        default = pkgs.vpsadmin-api;
        description = "Which vpsAdmin API package to use.";
        example = "pkgs.vpsadmin-api.override { ruby = pkgs.ruby_2_7; }";
      };

      user = mkOption {
        type = types.str;
        default = "vpsadmin-api";
        description = "User under which the API is ran.";
      };

      group = mkOption {
        type = types.str;
        default = "vpsadmin-api";
        description = "Group under which the API is ran.";
      };

      address = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address on which the API is ran.";
      };

      port = mkOption {
        type = types.int;
        default = 9292;
        description = "Port on which the API is ran.";
      };

      servers = mkOption {
        type = types.int;
        default = 1;
        description = ''
          Number of servers to run. Subsequent servers use incremented port
          number.
        '';
      };

      stateDir = mkOption {
        type = types.str;
        default = "${vpsadminCfg.stateDir}/api";
        description = "The state directory, logs and plugins are stored here.";
      };

      plugins = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "List of plugins to enable.";
      };

      configDirectory = mkOption {
        type = types.path;
        default = <vpsadmin/api/config>;
        description = "Directory with vpsAdmin configuration files";
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
          default = "vpsadmin-api";
          description = "Database user.";
        };

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = "/run/keys/vpsadmin-api-dbpassword";
          description = ''
            A file containing the password corresponding to
            <option>database.user</option>.
          '';
        };

        socket = mkOption {
          type = types.nullOr types.path;
          default =
            if cfg.database.createLocally then
              "/run/mysqld/mysqld.sock"
            else
             null;
          defaultText = "/run/mysqld/mysqld.sock";
          example = "/run/mysqld/mysqld.sock";
          description = "Path to the unix socket file to use for authentication.";
        };

        createLocally = mkOption {
          type = types.bool;
          default = false;
          description = "Create the database and database user locally.";
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
      "d '${cfg.stateDir}/cache' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/config' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/log' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/pids' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDir}/plugins' 0750 ${cfg.user} ${cfg.group} - -"

      "d /run/vpsadmin/api - - - - -"
      "L+ /run/vpsadmin/api/config - - - - ${cfg.stateDir}/config"
      "L+ /run/vpsadmin/api/log - - - - ${cfg.stateDir}/log"
      "L+ /run/vpsadmin/api/plugins - - - - ${cfg.stateDir}/plugins"
    ];

    systemd.services.vpsadmin-api = {
      after =
        [ "network.target" ]
        ++ optional cfg.database.createLocally [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      environment.SCHEMA = "${cfg.stateDir}/cache/structure.sql";
      path = with pkgs; [
        mariadb
      ];
      preStart = ''
        # Cleanup previous state
        rm -f "${cfg.stateDir}/plugins/"*
        find "${cfg.stateDir}/config" -type l -exec rm -f {} +

        # Link in configuration
        for v in "${cfg.configDirectory}"/* ; do
          ln -sf "$v" "${cfg.stateDir}/config/$(basename $v)"
        done

        # Link in enabled plugins
        for plugin in ${concatStringsSep " " cfg.plugins}; do
          ln -sf "${cfg.package}/plugins/$plugin" "${cfg.stateDir}/plugins/$plugin"
        done

        # Handle database.passwordFile & permissions
        DBPASS=${optionalString (cfg.database.passwordFile != null) "$(head -n1 ${cfg.database.passwordFile})"}
        cp -f ${databaseYml} "${cfg.stateDir}/config/database.yml"
        sed -e "s,#dbpass#,$DBPASS,g" -i "${cfg.stateDir}/config/database.yml"
        chmod 440 "${cfg.stateDir}/config/database.yml"

        # Run database migrations
        ${bundle} exec rake db:migrate
        ${bundle} exec rake vpsadmin:plugins:migrate
      '';

      serviceConfig =
        let
          thin = "${bundle} exec thin --config ${thinYml}";
        in {
          Type = "forking";
          User = cfg.user;
          Group = cfg.group;
          TimeoutStartSec = "infinity";
          TimeoutStopSec = (cfg.servers * serverWait) + 5;
          WorkingDirectory = "${cfg.package}/api";
          ExecStart="${thin} start";
          ExecStop = "${thin} stop";
          ExecReload = "${thin} restart";
        };
    };

    users.users = optionalAttrs (cfg.user == "vpsadmin-api") {
      ${cfg.user} = {
        group = cfg.group;
        home = cfg.stateDir;
        isSystemUser = true;
      };
    };

    users.groups = optionalAttrs (cfg.group == "vpsadmin-api") {
      ${cfg.group} = {};
    };
  };
}
