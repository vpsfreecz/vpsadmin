{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.redis;

  redisSrvCfg = config.services.redis.servers.vpsadmin;
in {
  options = {
    vpsadmin.redis = {
      enable = mkEnableOption "Enable redis for vpsAdmin";

      passwordFile = mkOption {
        type = types.path;
        description = ''
          File with password to the database.

          Passed to <option>services.redis.servers.vpsadmin.requirePassFile</option>.
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
        iptables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString redisSrvCfg.port} -j nixos-fw-accept
      '') cfg.allowedIPv4Ranges)
      ++
      (map (ip: ''
        ip6tables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString redisSrvCfg.port} -j nixos-fw-accept
      '') cfg.allowedIPv6Ranges)
    );

    services.redis.servers.vpsadmin = {
      enable = true;
      bind = null;
      port = 6379;
      requirePassFile = cfg.passwordFile;
    };
  };
}
