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
            default = { };
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

  taskDescription =
    name: task: if isNull task.description then "vpsAdmin API rake task ${name}" else task.description;

  activeRakeServices = filterAttrs (name: task: task.enable) cfg.rake.tasks;

  activeRakeTimers = filterAttrs (name: task: task.enable && task.timer.enable) cfg.rake.tasks;

  rakeServices = mapAttrsToList (name: task: {
    "vpsadmin-api-${name}" = {
      description = taskDescription name task;
      after = [
        "network.target"
        "vpsadmin-api.service"
      ] ++ optional cfg.database.createLocally [ "mysql.service" ];
      environment.RACK_ENV = "production";
      environment.SCHEMA = "${cfg.stateDirectory}/cache/structure.sql";
      path = with pkgs; [
        mariadb
      ];
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/api";
        ExecStart = "${bundle} exec rake ${toString task.rake}";
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

  userExpirationGraceDays = 14;
in
{
  options = {
    vpsadmin.api.rake = {
      enableDefaultTasks = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable default rake tasks
        '';
      };

      tasks = mkOption {
        type = types.attrsOf (types.submodule rakeTask);
        default = { };
        description = ''
          Rake tasks
        '';
      };
    };
  };

  config = mkMerge [
    (mkIf (cfg.enable && cfg.rake.enableDefaultTasks) {
      vpsadmin.api.rake.tasks = {
        auth-tokens = {
          rake = [
            "vpsadmin:auth:close_expired"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "5min";
          };
        };

        user-sessions = {
          rake = [
            "vpsadmin:user_session:close_expired"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "5min";
          };
        };

        report-failed-logins = {
          rake = [
            "vpsadmin:auth:report_failed_logins"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "60min";
            OnUnitActiveSec = "60min";
          };
        };

        migration-plans = {
          rake = [ "vpsadmin:vps:migration:run_plans" ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "*-*-* 08:00:00";
          };
        };

        mail-process = {
          rake = [
            "vpsadmin:mail:process"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "1h";
            OnUnitActiveSec = "10min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        monitoring-check = {
          rake = [ "vpsadmin:monitoring:check" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "10min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        monitoring-close = {
          rake = [ "vpsadmin:monitoring:close" ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "daily";
            RandomizedDelaySec = "900s";
            FixedRandomDelay = true;
          };
        };

        monitoring-prune = {
          rake = [ "vpsadmin:monitoring:prune" ];
          service.config = {
            TimeoutStartSec = "infinity";
          };
          timer.enable = true;
          timer.config = {
            OnCalendar = "daily";
            RandomizedDelaySec = "900s";
            FixedRandomDelay = true;
          };
        };

        incident-reports = {
          rake = [ "vpsadmin:incident_report:process" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "2min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        oom-reports-run = {
          rake = [ "vpsadmin:oom_report:run" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "10min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        oom-reports-prune = {
          rake = [ "vpsadmin:oom_report:prune" ];
          service.config = {
            TimeoutStartSec = "infinity";
          };
          timer.enable = true;
          timer.config = {
            OnCalendar = "daily";
            RandomizedDelaySec = "900s";
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

        vps-status-logs-prune = {
          rake = [ "vpsadmin:vps:prune_status_logs" ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "daily";
            RandomizedDelaySec = "900s";
            FixedRandomDelay = true;
          };
        };

        dataset-property-logs-prune = {
          rake = [ "vpsadmin:dataset:prune_property_logs" ];
          service.config = {
            TimeoutStartSec = "infinity";
          };
          timer.enable = true;
          timer.config = {
            OnCalendar = "daily";
            RandomizedDelaySec = "900s";
            FixedRandomDelay = true;
          };
        };

        daily-report = {
          rake = [ "vpsadmin:mail_daily_report" ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "*-*-* 09:00:00";
          };
        };

        mail-user-expiration-regular = {
          rake = [
            "vpsadmin:lifetimes:mail"
            "OBJECTS=User"
            "STATES=active"
            "FROM_DAYS=-7"
            "FORCE_DAY=${toString (userExpirationGraceDays - 1)}"
            "FORCE_ONLY=no"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "Mon,Wed,Fri 08:00:00";
          };
        };

        mail-user-expiration-forced = {
          rake = [
            "vpsadmin:lifetimes:mail"
            "OBJECTS=User"
            "STATES=active"
            "FROM_DAYS=-7"
            "FORCE_DAY=${toString (userExpirationGraceDays - 1)}"
            "FORCE_ONLY=yes"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "Tue,Thu,Sat,Sun 08:00:00";
          };
        };

        mail-vps-expiration-regular = {
          rake = [
            "vpsadmin:lifetimes:mail"
            "OBJECTS=Vps"
            "STATES=active"
            "FROM_DAYS=-7"
            "FORCE_DAY=-1"
            "FORCE_ONLY=no"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "Mon,Wed,Fri 08:00:00";
          };
        };

        mail-vps-expiration-forced = {
          rake = [
            "vpsadmin:lifetimes:mail"
            "OBJECTS=Vps"
            "STATES=active"
            "FROM_DAYS=-7"
            "FORCE_DAY=-1"
            "FORCE_ONLY=yes"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "Tue,Thu,Sat,Sun 08:00:00";
          };
        };

        users-suspend = {
          description = "Suspend expired users";
          rake = [
            "vpsadmin:lifetimes:progress"
            "OBJECTS=User"
            "STATES=active"
            "GRACE=${toString (userExpirationGraceDays * 24 * 60 * 60)}"
            "NEW_EXPIRATION=${toString (21 * 24 * 60 * 60)}"
            "REASON_CS=\"Nezaplacení členského příspěvku\""
            "REASON_EN=\"The membership fee wasn't paid\""
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "Tue..Fri, 00:15";
          };
        };

        users-soft-delete = {
          description = "Soft-delete expired suspended users";
          rake = [
            "vpsadmin:lifetimes:progress"
            "OBJECTS=User"
            "STATES=suspended"
            "NEW_EXPIRATION=${toString (30 * 24 * 60 * 60)}"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "00:20";
          };
        };

        users-hard-delete = {
          description = "Hard-delete soft-deleted users";
          rake = [
            "vpsadmin:lifetimes:progress"
            "OBJECTS=User"
            "STATES=soft_delete"
            "NEW_EXPIRATION=${toString (5 * 12 * 30 * 24 * 60 * 60)}"
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
          timer.config = {
            OnCalendar = "00:25";
          };
        };

        others-expire = {
          description = "Expire snapshot downloads, mounts, exports and datasets";
          rake = [
            "vpsadmin:lifetimes:progress"
            "OBJECTS=SnapshotDownload,Mount,Export,Dataset"
            "EXECUTE=yes"
          ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "00:35";
          };
        };

        prometheus-export-base = {
          rake = [
            "vpsadmin:prometheus:export:base"
            "EXPORT_FILE=${cfg.stateDirectory}/cache/vpsadmin-base.prom"
          ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "1min";
            OnUnitActiveSec = "2min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        prometheus-export-dns-records = {
          rake = [
            "vpsadmin:prometheus:export:dns_records"
            "EXPORT_FILE=${cfg.stateDirectory}/cache/vpsadmin-dns-records.prom"
          ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "10min";
            OnUnitActiveSec = "10min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        dataset-expansion-run = {
          rake = [ "vpsadmin:dataset_expansion:run" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "10min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        payments-process = {
          enable = elem "payments" vpsadminCfg.plugins;
          rake = [
            "vpsadmin:payments:process"
            "BACKEND=fio"
          ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "10min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };

        payments-report = {
          enable = elem "payments" vpsadminCfg.plugins;
          rake = [ "vpsadmin:payments:mail_overview" ];
          timer.enable = true;
          timer.config = {
            OnCalendar = "*-*-* 23:00:00";
          };
        };

        requests-ipqs = {
          enable = elem "requests" vpsadminCfg.plugins;
          rake = [ "vpsadmin:requests:check_registrations" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitInactiveSec = "2min";
            RandomizedDelaySec = "10s";
          };
        };

        outage-reports-auto-resolve = {
          enable = elem "outage_reports" vpsadminCfg.plugins;
          rake = [ "vpsadmin:outage_reports:auto_resolve" ];
          timer.enable = true;
          timer.config = {
            OnBootSec = "5min";
            OnUnitActiveSec = "2min";
            RandomizedDelaySec = "60s";
            FixedRandomDelay = true;
          };
        };
      };
    })

    (mkIf (cfg.enable && cfg.rake.enableDefaultTasks) {
      systemd.services."vpsadmin-api-prometheus-export-base" = {
        wants = [ "vpsadmin-api-prometheus-export-deploy.service" ];
        before = [ "vpsadmin-api-prometheus-export-deploy.service" ];
      };

      systemd.services."vpsadmin-api-prometheus-export-dns-records" = {
        wants = [ "vpsadmin-api-prometheus-export-deploy.service" ];
        before = [ "vpsadmin-api-prometheus-export-deploy.service" ];
      };

      systemd.services."vpsadmin-api-prometheus-export-deploy" = {
        description = "Copy vpsAdmin metrics from the cache directory to node_exporter";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeScript "vpsadmin-api-prometheus-export-deploy" ''
            #!${pkgs.bash}/bin/bash
            src="${cfg.stateDirectory}/cache/vpsadmin-*.prom"
            dst="${cfg.nodeExporterTextCollectorDirectory}"

            mkdir -p "$dst"

            for srcfile in $src ; do
              basename=$(basename "$srcfile")
              dstfile="$dst/$basename"

              mv "$srcfile" "$dstfile.new" || exit 1
              mv "$dstfile.new" "$dstfile" || exit 1
            done

            exit 0
          '';
        };
      };
    })

    (mkIf cfg.enable {
      systemd.services = mkMerge rakeServices;
      systemd.timers = mkMerge rakeTimers;
    })
  ];
}
