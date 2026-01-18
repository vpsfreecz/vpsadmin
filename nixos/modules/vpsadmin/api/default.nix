{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.api;

  apiApp = import ../api-app.nix {
    name = "api";
    inherit config pkgs lib;
    inherit (cfg)
      package
      user
      group
      configDirectory
      stateDirectory
      ;
    databaseConfig = cfg.database;
  };

  pumaConfig = pkgs.writeText "puma.rb" ''
    bind 'tcp://${cfg.address}:${toString cfg.port}'
    rackup '${cfg.package}/api/config.ru'
    threads ${toString cfg.threads.min}, ${toString cfg.threads.max}
    workers ${toString cfg.workers}
    environment 'production'
    tag 'api'
  '';
in
{
  imports = apiApp.imports;

  options = {
    vpsadmin.api = {
      enable = mkEnableOption "Enable vpsAdmin API server";

      package = mkOption {
        type = types.package;
        default = pkgs.vpsadmin-api;
        description = "Which vpsAdmin API package to use.";
        example = "pkgs.vpsadmin-api.override { ruby = pkgs.ruby_3_4; }";
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

      threads.min = mkOption {
        type = types.int;
        default = 0;
        description = ''
          Minimum number of threads per worker
        '';
      };

      threads.max = mkOption {
        type = types.int;
        default = 5;
        description = ''
          Maximum number of threads per worker
        '';
      };

      workers = mkOption {
        type = types.int;
        default = 2;
        description = ''
          Number of worker processes to run
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
        default = [ ];
        description = ''
          List of IPv4 ranges to be allowed access to the server within the firewall
        '';
      };

      allowedIPv6Ranges = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          List of IPv6 ranges to be allowed access to the server within the firewall
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
        type = types.submodule (apiApp.databaseModule { });
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

    networking.firewall.extraCommands = concatStringsSep "\n" (
      flatten (
        (map (ip: ''
          iptables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString cfg.port} -j nixos-fw-accept
        '') cfg.allowedIPv4Ranges)
        ++ (map (ip: ''
          ip6tables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString cfg.port} -j nixos-fw-accept
        '') cfg.allowedIPv6Ranges)
      )
    );

    systemd.tmpfiles.rules = apiApp.tmpfilesRules ++ [
      "d '${cfg.stateDirectory}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/cache' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/log' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/pids' 0750 ${cfg.user} ${cfg.group} - -"

      "d /run/vpsadmin/api - - - - -"
      "L+ /run/vpsadmin/api/log - - - - ${cfg.stateDirectory}/log"
    ];

    systemd.services.vpsadmin-api = {
      after = [
        "network.target"
        "vpsadmin-database-setup.service"
      ];
      requires = [ "vpsadmin-database-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      environment.SCHEMA = "${cfg.stateDirectory}/cache/schema.rb";
      path = with pkgs; [
        mariadb
      ];
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      preStart = apiApp.setup;

      serviceConfig = {
        Type = "notify";
        User = cfg.user;
        Group = cfg.group;
        TimeoutStartSec = "infinity";
        TimeoutStopSec = 90;
        WorkingDirectory = "${cfg.package}/api";
        ExecStart = "${apiApp.bundle} exec puma -C ${pumaConfig}";
        Restart = "on-failure";
        RestartSec = 30;
        WatchdogSec = 10;
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
      ${cfg.group} = { };
    };

    # ExceptionMailer extension in HaveAPI needs sendmail to send errors over
    # mail
    services.postfix.enable = true;
  };
}
