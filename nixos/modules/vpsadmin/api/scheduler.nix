{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.api;

  bundle = "${cfg.package}/ruby-env/bin/bundle";
in {
  options = {
    vpsadmin.api = {
      scheduler = {
        enable = mkEnableOption "Enable vpsAdmin scheduler";
      };
    };
  };

  config = mkIf (cfg.enable && cfg.scheduler.enable) {
    nixpkgs.overlays = [
      (self: super: { cron = super.callPackage ../../../../packages/cronie {}; })
    ];

    systemd.tmpfiles.rules = [
      "f /etc/cron.d/vpsadmin 0644 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.vpsadmin-scheduler = {
      after =
        [ "network.target" "vpsadmin-api.service" ]
        ++ optional cfg.database.createLocally [ "mysql.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      environment.SCHEDULER_SOCKET = "${cfg.stateDir}/scheduler.sock";
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/api";
        ExecStart="${bundle} exec bin/vpsadmin-scheduler";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };

    services.cron = {
      enable = true;
      permitAnyCrontab = true;
    };
  };
}
