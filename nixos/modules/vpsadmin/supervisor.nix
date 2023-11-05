{ config, pkgs, lib, ... }:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.supervisor;

  apiApp = import ./api-app.nix {
    name = "supervisor";
    inherit config pkgs lib;
    inherit (cfg) package user group configDirectory stateDirectory;
    databaseConfig = cfg.database;
  };

  rabbitmqYml = pkgs.writeText "rabbitmq.yml" (builtins.toJSON {
    hosts = cfg.rabbitmq.hosts;
    vhost = cfg.rabbitmq.virtualHost;
    username = cfg.rabbitmq.username;
    password = "#rabbitmq_pass#";
    servers = cfg.servers;
    foreground = false;
  });
in {
  options = {
    vpsadmin.supervisor = {
      enable = mkEnableOption "Enable vpsAdmin supervisor";

      package = mkOption {
        type = types.package;
        default = pkgs.vpsadmin-supervisor;
        description = "Which vpsAdmin API package to use.";
        example = "pkgs.vpsadmin-supervisor.override { ruby = pkgs.ruby_3_1; }";
      };

      user = mkOption {
        type = types.str;
        default = "vpsadmin-supervisor";
        description = "User under which the supervisor is run";
      };

      group = mkOption {
        type = types.str;
        default = "vpsadmin-supervisor";
        description = "Group under which the supervisor is run";
      };

      servers = mkOption {
        type = types.int;
        default = 1;
        description = ''
          Number of servers to run
        '';
      };

      stateDirectory = mkOption {
        type = types.str;
        default = "${vpsadminCfg.stateDirectory}/supervisor";
        description = "The state directory, logs and plugins are stored here.";
      };

      configDirectory = mkOption {
        type = types.path;
        default = <vpsadmin/api/config>;
        description = "Directory with vpsAdmin configuration files";
      };

      rabbitmq = {
        hosts = mkOption {
          type = types.listOf types.str;
          description = ''
            A list of rabbitmq hosts to connect to
          '';
        };

        virtualHost = mkOption {
          type = types.str;
          default = "/";
          description = ''
            rabbitmq virtual host
          '';
        };

        username = mkOption {
          type = types.str;
          description = ''
            Username
          '';
        };

        passwordFile = mkOption {
          type = types.str;
          description = ''
            Path to file containing password
          '';
        };
      };

      database = mkOption {
        type = types.submodule (apiApp.databaseModule {pool = 15;});
        description = ''
          Database configuration
        '';
      };
    };
  };

  config = mkIf (cfg.enable) {
    vpsadmin = {
      enableOverlay = true;
      enableStateDirectory = true;
    };

    systemd.tmpfiles.rules = apiApp.tmpfilesRules;

    systemd.services.vpsadmin-supervisor = {
      after =
        [ "network.target" ]
        ++ optional cfg.database.createLocally [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      preStart = ''
        ${apiApp.setup}

        RABBITMQ_PASS=${optionalString (cfg.rabbitmq.passwordFile != null) "$(head -n1 ${cfg.rabbitmq.passwordFile})"}
        cp -f ${rabbitmqYml} "${cfg.stateDirectory}/config/supervisor.yml"
        sed -e "s,#rabbitmq_pass#,$RABBITMQ_PASS,g" -i "${cfg.stateDirectory}/config/supervisor.yml"
        chmod 440 "${cfg.stateDirectory}/config/supervisor.yml"
      '';
      serviceConfig = {
        Type = "forking";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/supervisor";
        ExecStart="${apiApp.bundle} exec bin/vpsadmin-supervisor";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };

    users.users = optionalAttrs (cfg.user == "vpsadmin-supervisor") {
      ${cfg.user} = {
        group = cfg.group;
        home = cfg.stateDirectory;
        isSystemUser = true;
      };
    };

    users.groups = optionalAttrs (cfg.group == "vpsadmin-supervisor") {
      ${cfg.group} = {};
    };
  };
}
