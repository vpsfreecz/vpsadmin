{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.api.backend;

  bundle = "${cfg.package}/ruby-env/bin/bundle";
in {
  options = {
    vpsadmin.api.backend = {
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
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/api";
        ExecStart="${bundle} exec bin/vpsadmin-scheduler";
      };
    };

    services.cron = {
      enable = true;
      permitAnyCrontab = true;
    };
  };
}
