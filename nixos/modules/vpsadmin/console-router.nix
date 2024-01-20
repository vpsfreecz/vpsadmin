{ config, pkgs, lib, ... }:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.console-router;

  bundle = "${cfg.package}/ruby-env/bin/bundle";

  rabbitmqYml = pkgs.writeText "rabbitmq.yml" (builtins.toJSON {
    hosts = vpsadminCfg.rabbitmq.hosts;
    vhost = vpsadminCfg.rabbitmq.virtualHost;
    username = cfg.rabbitmq.username;
    password = "#rabbitmq_pass#";
  });

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
        example = "pkgs.vpsadmin-console-router.override { ruby = pkgs.ruby_3_2; }";
      };

      user = mkOption {
        type = types.str;
        default = "vpsadmin-console";
        description = "User under which the console router is run";
      };

      group = mkOption {
        type = types.str;
        default = "vpsadmin-console";
        description = "Group under which the console router is run";
      };

      address = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address on which the console router is run";
      };

      port = mkOption {
        type = types.int;
        default = 8000;
        description = "Port on which the console router is run";
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

      rabbitmq = {
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
        RABBITMQ_PASS=${optionalString (cfg.rabbitmq.passwordFile != null) "$(head -n1 ${cfg.rabbitmq.passwordFile})"}
        cp -f ${rabbitmqYml} "${cfg.stateDirectory}/config/rabbitmq.yml"
        sed -e "s,#rabbitmq_pass#,$RABBITMQ_PASS,g" -i "${cfg.stateDirectory}/config/rabbitmq.yml"
        chmod 440 "${cfg.stateDirectory}/config/rabbitmq.yml"
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
