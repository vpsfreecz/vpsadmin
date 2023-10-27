{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.rabbitmq;

  ports = [
    4369      # empd
    5672 5671 # AMQP clients
    25672     # inter-node communication
    15692     # prometheus metrics
    config.services.rabbitmq.managementPlugin.port
  ];
in {
  options = {
    vpsadmin.rabbitmq = {
      enable = mkEnableOption "Enable rabbitmq for vpsAdmin";

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
    networking.firewall.extraCommands = ''
      ${concatMapStringsSep "\n" (ip: concatMapStringsSep "\n" (port: ''
      iptables -A nixos-fw -p tcp -s ${ip} --dport ${toString port} -j nixos-fw-accept
      '') ports) cfg.allowedIPv4Ranges}

      ${concatMapStringsSep "\n" (ip: concatMapStringsSep "\n" (port: ''
      ip6tables -A nixos-fw -p tcp -s ${ip} --dport ${toString port} -j nixos-fw-accept
      '') ports) cfg.allowedIPv6Ranges}
    '';

    services.rabbitmq = {
      enable = true;
      listenAddress = "0.0.0.0";
      configItems = {
        # "listeners.tcp.1" = "5672";
      };
      managementPlugin.enable = true;
    };
  };
}
