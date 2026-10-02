{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.vpsadmin.api;

  bundle = "${cfg.package}/ruby-env/bin/bundle";
in
{
  options = {
    vpsadmin.api = {
      scheduler = {
        enable = mkEnableOption "Enable vpsAdmin scheduler";
        taskRefreshInterval = mkOption {
          type = types.ints.positive;
          default = 10800;
          description = "Seconds between reloads of repeatable tasks from the database.";
        };
      };
    };
  };

  config = mkIf (cfg.enable && cfg.scheduler.enable) {
    systemd.services.vpsadmin-scheduler = {
      after = [
        "network.target"
        "vpsadmin-api.service"
      ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      environment.SCHEDULER_SOCKET = "${cfg.stateDirectory}/scheduler.sock";
      environment.SCHEDULER_TASK_REFRESH_INTERVAL = toString cfg.scheduler.taskRefreshInterval;
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/api";
        ExecStart = "${bundle} exec bin/vpsadmin-scheduler";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };
  };
}
