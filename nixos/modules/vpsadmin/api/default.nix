{ config, pkgs, lib, ... }:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.api;

  apiApp = import ../api-app.nix {
    name = "api";
    inherit config pkgs lib;
    inherit (cfg) package user group configDirectory stateDirectory;
    databaseConfig = cfg.database;
  };

  serverWait = 90;

  thinYml = pkgs.writeText "thin.yml" ''
    address: ${cfg.address}
    port: ${toString cfg.port}
    servers: ${toString cfg.servers}
    rackup: ${cfg.package}/api/config.ru
    pid: ${cfg.stateDirectory}/pids/thin.pid
    log: ${cfg.stateDirectory}/log/thin.log
    daemonize: true
    onebyone: true
    environment: production
    wait: ${toString serverWait}
    tag: api
  '';

  forAllPorts = fn: genList (i: fn (cfg.port + i)) cfg.servers;
in {
  imports = apiApp.imports;

  options = {
    vpsadmin.api = {
      enable = mkEnableOption "Enable vpsAdmin API server";

      package = mkOption {
        type = types.package;
        default = pkgs.vpsadmin-api;
        description = "Which vpsAdmin API package to use.";
        example = "pkgs.vpsadmin-api.override { ruby = pkgs.ruby_3_1; }";
      };

      user = mkOption {
        type = types.str;
        default = "vpsadmin-api";
        description = "User under which the API is run";
      };

      group = mkOption {
        type = types.str;
        default = "vpsadmin-api";
        description = "Group under which the API is run";
      };

      address = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address on which the API is run";
      };

      port = mkOption {
        type = types.int;
        default = 9292;
        description = "Port on which the API is run";
      };

      servers = mkOption {
        type = types.int;
        default = 1;
        description = ''
          Number of servers to run. Subsequent servers use incremented port
          number.
        '';
      };

      stateDirectory = mkOption {
        type = types.str;
        default = "${vpsadminCfg.stateDirectory}/api";
        description = "The state directory, logs and plugins are stored here.";
      };

      configDirectory = mkOption {
        type = types.path;
        default = <vpsadmin/api/config>;
        description = "Directory with vpsAdmin configuration files";
      };

      allowedIPv4Ranges = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          List of IPv4 ranges to be allowed access to the servers within the firewall
        '';
      };

      allowedIPv6Ranges = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          List of IPv6 ranges to be allowed access to the servers within the firewall
        '';
      };

      nodeExporterTextCollectorDirectory = mkOption {
        type = types.str;
        default = "/run/metrics";
        description = ''
          Path to a directory, which is read by node_exporter's text file
          collector. Rake tasks may place their files there.
        '';
      };

      database = mkOption {
        type = types.submodule (apiApp.databaseModule {});
        description = ''
          Database configuration
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    vpsadmin = {
      enableOverlay = true;
      enableStateDirectory = true;

      api.rake.tasks = {
        migrate-db = {
          description = "Run database migrations";
          rake = [ "db:migrate" ];
          service.config = {
            TimeoutStartSec = "infinity";
          };
        };

        migrate-plugins = {
          description = "Run plugin database migrations";
          rake = [ "vpsadmin:plugins:migrate" ];
          service.config = {
            TimeoutStartSec = "infinity";
          };
        };
      };
    };

    networking.firewall.extraCommands = concatStringsSep "\n" (flatten (
      (map (ip: forAllPorts (port: ''
        iptables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString port} -j nixos-fw-accept
      '')) cfg.allowedIPv4Ranges)
      ++
      (map (ip: forAllPorts (port: ''
        ip6tables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString port} -j nixos-fw-accept
      '')) cfg.allowedIPv6Ranges)
    ));

    systemd.tmpfiles.rules = apiApp.tmpfilesRules ++ [
      "d '${cfg.stateDirectory}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/cache' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/log' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/pids' 0750 ${cfg.user} ${cfg.group} - -"

      "d /run/vpsadmin/api - - - - -"
      "L+ /run/vpsadmin/api/log - - - - ${cfg.stateDirectory}/log"
    ];

    systemd.services.vpsadmin-api = {
      after =
        [ "network.target" ]
        ++ optional cfg.database.createLocally [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      environment.SCHEMA = "${cfg.stateDirectory}/cache/structure.sql";
      path = with pkgs; [
        mariadb
      ];
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      preStart = apiApp.setup;

      serviceConfig =
        let
          thin = "${apiApp.bundle} exec thin --config ${thinYml}";
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
          Restart = "on-failure";
          RestartSec = 30;
        };
    };

    users.users = optionalAttrs (cfg.user == "vpsadmin-api") {
      ${cfg.user} = {
        group = cfg.group;
        home = cfg.stateDirectory;
        isSystemUser = true;
      };
    };

    users.groups = optionalAttrs (cfg.group == "vpsadmin-api") {
      ${cfg.group} = {};
    };

    # ExceptionMailer extension in HaveAPI needs sendmail to send errors over
    # mail
    services.postfix.enable = true;
  };
}
