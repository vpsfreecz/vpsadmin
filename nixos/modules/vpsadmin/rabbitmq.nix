{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.vpsadmin.rabbitmq;

  ports = {
    cluster = [
      4369 # empd
      25672 # inter-node communication
    ];

    clients = [
      5672
      5671 # AMQP clients
    ];

    management = [
      config.services.rabbitmq.managementPlugin.port
    ];

    monitoring = [
      15692 # prometheus metrics
    ];
  };

  rangeOption =
    ipVersion:
    mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        List of IPv${ipVersion} ranges to be allowed access to the server within the firewall
      '';
    };

  allowedRanges = ipVersion: {
    cluster = rangeOption ipVersion;

    clients = rangeOption ipVersion;

    management = rangeOption ipVersion;

    monitoring = rangeOption ipVersion;
  };

  mkIptablesRules =
    ipVersion:
    let
      iptables = if ipVersion == "4" then "iptables" else "ip6tables";

      ranges = if ipVersion == "4" then cfg.allowedIPv4Ranges else cfg.allowedIPv6Ranges;
    in
    ''
      # rabbitmq inter-node communication ports
      ${concatMapStringsSep "\n" (
        ip:
        concatMapStringsSep "\n" (port: ''
          ${iptables} -A nixos-fw -p tcp -s ${ip} --dport ${toString port} -j nixos-fw-accept
        '') ports.cluster
      ) ranges.cluster}

      # rabbitmq client ports
      ${concatMapStringsSep "\n" (
        ip:
        concatMapStringsSep "\n" (port: ''
          ${iptables} -A nixos-fw -p tcp -s ${ip} --dport ${toString port} -j nixos-fw-accept
        '') ports.clients
      ) ranges.clients}

      # rabbitmq management ports
      ${concatMapStringsSep "\n" (
        ip:
        concatMapStringsSep "\n" (port: ''
          ${iptables} -A nixos-fw -p tcp -s ${ip} --dport ${toString port} -j nixos-fw-accept
        '') ports.management
      ) ranges.management}

      # rabbitmq monitoring ports
      ${concatMapStringsSep "\n" (
        ip:
        concatMapStringsSep "\n" (port: ''
          ${iptables} -A nixos-fw -p tcp -s ${ip} --dport ${toString port} -j nixos-fw-accept
        '') ports.monitoring
      ) ranges.monitoring}
    '';
in
{
  options = {
    vpsadmin.rabbitmq = {
      enable = mkEnableOption "Enable rabbitmq for vpsAdmin";

      initialScript = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Path to an executable script which is run on the first startup. Can be used
          to provide initial configuration.
        '';
      };

      allowedIPv4Ranges = allowedRanges "4";

      allowedIPv6Ranges = allowedRanges "6";
    };
  };

  config = mkIf cfg.enable {
    networking.firewall.extraCommands = concatStringsSep "\n\n" [
      (mkIptablesRules "4")
      (mkIptablesRules "6")
    ];

    services.rabbitmq = {
      enable = true;
      listenAddress = "0.0.0.0";
      configItems = {
        # "listeners.tcp.1" = "5672";
        cluster_partition_handling = "pause_minority";
      };
      managementPlugin.enable = true;
      plugins = [
        "rabbitmq_prometheus"
      ];
    };

    systemd.services.vpsadmin-rabbitmq-setup = mkIf (!isNull cfg.initialScript) {
      description = "Initial configuration for rabbitmq";
      wantedBy = [ "multi-user.target" ];
      after = [ "rabbitmq.service" ];
      requires = [ "rabbitmq.service" ];
      path = with pkgs; [ rabbitmq-server ];
      environment.HOME = "/root";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeScript "vpsadmin-rabbitmq-setup.sh" ''
          #!${pkgs.bash}/bin/bash

          stateDir="/var/lib/vpsadmin-rabbitmq"
          stateFile="$stateDir/rabbitmq-initialized"

          if [ -e "$stateFile" ]; then
            echo "rabbitmq is already initialized"
            exit 0
          fi

          echo "Initializing rabbitmq using ${cfg.initialScript}"

          ${cfg.initialScript}
          rc=$?

          [ "$rc" != "0" ] && exit $rc

          mkdir -p "$stateDir"
          date > "$stateFile"
          echo "rabbitmq initialized"
          exit 0
        '';
        RemainAfterExit = "yes";
      };
    };
  };
}
