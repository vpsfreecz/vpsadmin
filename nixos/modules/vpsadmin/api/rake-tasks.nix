{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.api.backend;

  bundle = "${cfg.package}/ruby-env/bin/bundle";

  rakeTask =
    { config, pkgs, ... }:
    {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable the rake task";
        };

        description = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Task description";
        };

        rake = mkOption {
          type = types.listOf types.str;
          description = "Rake task and arguments";
        };

        service = {
          config = mkOption {
            type = types.attrs;
            default = {};
            description = ''
              Options for the systemd service, see
              <option>systemd.timers.&lt;name&gt;serviceConfig</option>
            '';
          };
        };

        timer = {
          enable = mkEnableOption "Enable systemd timer for the rake task";

          config = mkOption {
            type = types.attrs;
            description = ''
              Options for the systemd timer, see
              <option>systemd.timers.&lt;name&gt;timerConfig</option>
            '';
          };
        };
      };
  };

  taskDescription = name: task:
    if isNull task.description then
      "vpsAdmin API rake task ${name}"
    else task.description;

  activeRakeServices =
    filterAttrs
      (name: task: task.enable)
      cfg.rake.tasks;

  activeRakeTimers =
    filterAttrs
      (name: task: task.enable && task.timer.enable)
      cfg.rake.tasks;

  rakeServices = mapAttrsToList (name: task: {
    "vpsadmin-api-${name}" = {
      description = taskDescription name task;
      after =
        [ "network.target" "vpsadmin-api.service" ]
        ++ optional cfg.database.createLocally [ "mysql.service" ];
      environment.RACK_ENV = "production";
      environment.SCHEMA = "${cfg.stateDir}/cache/structure.sql";
      path = with pkgs; [
        mariadb
      ];
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/api";
        ExecStart="${bundle} exec rake ${toString task.rake}";
        TimeoutStartSec = "1h";
      } // task.service.config;
    };
  }) activeRakeServices;

  rakeTimers = mapAttrsToList (name: task: {
    "vpsadmin-api-${name}" = mkIf task.timer.enable {
      description = taskDescription name task;
      wantedBy = [ "timers.target" ];
      timerConfig = task.timer.config;
    };
  }) activeRakeTimers;
in {
  options = {
    vpsadmin.api.backend.rake = {
      enableDefaultTasks = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable default rake tasks
        '';
      };

      tasks = mkOption {
        type = types.attrsOf (types.submodule rakeTask);
        default = {};
        description = ''
          Rake tasks
        '';
      };
    };
  };

  config = mkMerge [
    (mkIf (cfg.enable && cfg.rake.enableDefaultTasks) {
      vpsadmin.api.backend.rake.tasks = {
        auth-tokens = {
          rake = [ "vpsadmin:auth:close_expired" "EXECUTE=yes" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "5min";
          };
        };

        user-sessions = {
          rake = [ "vpsadmin:user_session:close_expired" "EXECUTE=yes" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "5min";
          };
        };

        process-transfers = {
          rake = [ "vpsadmin:transfers:process" ];
          timer.enable = true;
          timer.config = { OnCalendar = "minutely"; };
        };

        migration-plans = {
          rake = [ "vpsadmin:vps:migration:run_plans" ];
          timer.enable = true;
          timer.config = { OnCalendar = "*-*-* 08:00:00"; };
        };

        monitoring = {
          rake = [ "vpsadmin:monitoring:check" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "10min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        oom-reports = {
          rake = [ "vpsadmin:oom_report:run" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "10min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        purge-clones = {
          rake = [ "vpsadmin:snapshot:purge_clones" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "1h";
            OnUnitActiveSec = "6h";
            RandomizedDelaySec = "5min";
          };
        };

        daily-report = {
          rake = [ "vpsadmin:mail_daily_report" ];
          timer.enable = true;
          timer.config = { OnCalendar = "*-*-* 09:00:00"; };
        };

        mail-expiration = {
          rake = [ "vpsadmin:lifetimes:mail" "OBJECTS=User,Vps" "STATES=active" "DAYS=7" ];
          timer.enable = true;
          timer.config = { OnCalendar = "*-*-* 08:00:00"; };
        };

        users-suspend = {
          description = "Suspend expired users";
          rake = [
            "vpsadmin:lifetimes:progress"
            "OBJECTS=User"
            "STATES=active"
            "GRACE=${toString (14*24*60*60)}"
            "NEW_EXPIRATION=${toString (21*24*60*60)}"
            "REASON=\"Nezaplacení členského příspěvku\""
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = { OnCalendar = "Tue..Fri, 00:15"; };
        };

        users-soft-delete = {
          description = "Soft-delete expired suspended users";
          rake = [
            "vpsadmin:lifetimes:progress"
            "OBJECTS=User"
            "STATES=suspended"
            "NEW_EXPIRATION=${toString (30*24*60*60)}"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = { OnCalendar = "00:20"; };
        };

        users-hard-delete = {
          description = "Hard-delete soft-deleted users";
          rake = [
            "vpsadmin:lifetimes:progress"
            "OBJECTS=User"
            "STATES=soft_delete"
            "NEW_EXPIRATION=${toString (5*12*30*24*60*60)}"
            "EXECUTE=yes"
          ];
        };

        vpses-expire = {
          description = "Suspend and soft/hard delete VPSes";
          rake = [
            "vpsadmin:lifetimes:progress"
            "OBJECTS=Vps"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = { OnCalendar = "00:25"; };
        };

        others-expire = {
          description = "Expire snapshot downloads, mounts, exports and datasets";
          rake = [
            "vpsadmin:lifetimes:progress"
            "OBJECTS=SnapshotDownload,Mount,Export,Dataset"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = { OnCalendar = "00:35"; };
        };

        payments-process = {
          enable = elem "payments" cfg.plugins;
          rake = [ "vpsadmin:payments:process" "BACKEND=fio" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "10min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        payments-report = {
          enable = elem "payments" cfg.plugins;
          rake = [ "vpsadmin:payments:mail_overview" ];
          timer.enable = true;
          timer.config = { OnCalendar = "*-*-* 23:00:00"; };
        };

        requests-ipqs = {
          enable = elem "requests" cfg.plugins;
          rake = [ "vpsadmin:requests:check_registrations" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitInactiveSec = "2min";
            RandomizedDelaySec = "10s";
          };
        };
      };
    })

    (mkIf cfg.enable {
      systemd.services = mkMerge rakeServices;
      systemd.timers = mkMerge rakeTimers;
    })
  ];
}
