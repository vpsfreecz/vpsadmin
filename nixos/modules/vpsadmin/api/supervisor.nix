{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.api;

  bundle = "${cfg.package}/ruby-env/bin/bundle";

  rabbitmqYml = pkgs.writeText "rabbitmq.yml" (builtins.toJSON {
    hosts = cfg.rabbitmq.hosts;
    vhost = cfg.rabbitmq.virtualHost;
    username = cfg.rabbitmq.username;
    password = "#rabbitmq_pass#";
  });
in {
  options = {
    vpsadmin.api = {
      supervisor = {
        enable = mkEnableOption "Enable vpsAdmin supervisor";

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
      };
    };
  };

  config = mkIf (cfg.enable && cfg.supervisor.enable) {
    systemd.services.vpsadmin-supervisor = {
      after =
        [ "network.target" ]
        ++ optional cfg.database.createLocally [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      preStart = ''
        RABBITMQ_PASS=${optionalString (cfg.rabbitmq.passwordFile != null) "$(head -n1 ${cfg.rabbitmq.passwordFile})"}
        cp -f ${rabbitmqYml} "${cfg.stateDir}/config/supervisor.yml"
        sed -e "s,#rabbitmq_pass#,$RABBITMQ_PASS,g" -i "${cfg.stateDir}/config/supervisor.yml"
        chmod 440 "${cfg.stateDir}/config/supervisor.yml"
      '';
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/api";
        ExecStart="${bundle} exec bin/vpsadmin-supervisor";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
  };
}
