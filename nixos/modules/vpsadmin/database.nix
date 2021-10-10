{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.database;

  dbPort = config.services.mysql.port;
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
    };
  };
}
