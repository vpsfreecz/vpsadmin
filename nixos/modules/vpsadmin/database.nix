{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.database;

  dbPort = config.services.mysql.settings.mysqld.port;
in {
  options = {
    vpsadmin.database = {
      enable = mkEnableOption "Enable vpsAdmin database server";

      defaultConfig = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Apply default configuration
        '';
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
    };
  };

  config = mkIf cfg.enable {
    networking.firewall.extraCommands = concatStringsSep "\n" (
      (map (ip: ''
        iptables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString dbPort} -j nixos-fw-accept
      '') cfg.allowedIPv4Ranges)
      ++
      (map (ip: ''
        ip6tables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString dbPort} -j nixos-fw-accept
      '') cfg.allowedIPv6Ranges)
    );

    services.mysql = {
      enable = true;
      package = pkgs.mariadb;
      ensureDatabases = mkIf cfg.defaultConfig [ "vpsadmin" ];
      ensureUsers = mkIf cfg.defaultConfig [
        {
          name = "vpsadmin";
          ensurePermissions = {
            "vpsadmin.*" = "ALL PRIVILEGES";
          };
        }
      ];
      settings = {
        mysqld = {
          innodb_buffer_pool_size = mkDefault "14000M";
          innodb_flush_method = mkDefault "O_DSYNC";
          innodb_read_io_threads = mkDefault 32;
          innodb_write_io_threads = mkDefault 16;
          innodb_purge_threads = mkDefault 16;
          innodb_doublewrite = mkDefault 0;
          innodb_read_ahead_threshold = mkDefault 16;
          innodb_print_all_deadlocks = mkDefault 1;
          innodb_old_blocks_pct = mkDefault 90;
          innodb_io_capacity = mkDefault 25000;
          innodb_use_native_aio = mkDefault 0;

          slow_query_log = mkDefault 1;
          slow_query_log_file = mkDefault "${config.services.mysql.dataDir}/slow-query.log";
          long_query_time = mkDefault 1;

          log_bin = mkDefault "mysql-bin";
          expire_logs_days = mkDefault 7;
          max_binlog_size = mkDefault "1000M";
          sync_binlog = mkDefault 1;
          binlog_format = mkDefault "MIXED";

          max_allowed_packet = mkDefault "64M";

          join_buffer_size = mkDefault "256M";
          sort_buffer_size = mkDefault "512M";
          read_buffer_size = mkDefault "128M";

          max_connections = mkDefault 1000;
          tmp_table_size = mkDefault "96M";
          max_heap_table_size = mkDefault "1024M";
          table_definition_cache = mkDefault 65536;

          transaction_isolation = mkDefault "READ-COMMITTED";

          skip_name_resolve = mkDefault true;
        };
      };
    };
  };
}
