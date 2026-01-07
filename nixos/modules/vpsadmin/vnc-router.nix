{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin."vnc-router";

  defaultRabbitHost = head (vpsadminCfg.rabbitmq.hosts ++ [ "localhost" ]);

  rabbitmqVhost =
    let
      trimmed = removePrefix "/" cfg.rabbitmq.virtualHost;
      encoded = builtins.replaceStrings [ "/" ] [ "%2F" ] trimmed;
    in
    if cfg.rabbitmq.virtualHost == "/" then "%2F" else encoded;

  configJson = pkgs.writeText "vnc-router-config.json" (
    builtins.toJSON {
      listen_addr = "${cfg.address}:${toString cfg.port}";
      novnc_dir = cfg.novnc.dir;
      metrics_allowed_subnets = cfg.metrics.allowedSubnets;
      rabbitmq_url = "#rabbitmq_url#";
    }
  );
in
{
  options = {
    vpsadmin."vnc-router" = {
      enable = mkEnableOption "Enable vpsAdmin VNC router service";

      package = mkOption {
        type = types.package;
        default = pkgs.vpsadmin-vnc-router;
        description = "Which vpsAdmin VNC router package to use.";
      };

      user = mkOption {
        type = types.str;
        default = "vpsadmin-vnc";
        description = "User under which the VNC router is run.";
      };

      group = mkOption {
        type = types.str;
        default = "vpsadmin-vnc";
        description = "Group under which the VNC router is run.";
      };

      address = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Address on which the VNC router listens.";
      };

      port = mkOption {
        type = types.int;
        default = 8001;
        description = "Port on which the VNC router listens.";
      };

      debug = mkOption {
        type = types.bool;
        default = false;
        description = "Enable debug logging.";
      };

      stateDirectory = mkOption {
        type = types.str;
        default = "${vpsadminCfg.stateDirectory}/vnc_router";
        description = "The state directory for vnc_router runtime files.";
      };

      allowedIPv4Ranges = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          List of IPv4 ranges to be allowed access to the server within the firewall
        '';
      };

      allowedIPv6Ranges = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          List of IPv6 ranges to be allowed access to the server within the firewall
        '';
      };

      metrics.allowedSubnets = mkOption {
        type = types.listOf types.str;
        default = [ "127.0.0.1/32" ];
        description = "List of subnets allowed to access /metrics.";
      };

      novnc = {
        package = mkOption {
          type = types.package;
          default = pkgs.novnc;
          description = "noVNC package to serve static assets from.";
        };

        dir = mkOption {
          type = types.nullOr types.str;
          default = null;
          defaultText = "${cfg.novnc.package}/share/webapps/novnc";
          apply = v: if v == null then "${cfg.novnc.package}/share/webapps/novnc" else v;
          description = "Directory with noVNC static assets.";
        };
      };

      rabbitmq = {
        scheme = mkOption {
          type = types.str;
          default = "amqp";
          description = "RabbitMQ URL scheme, usually amqp or amqps.";
        };

        host = mkOption {
          type = types.str;
          default = defaultRabbitHost;
          description = "RabbitMQ host name.";
        };

        port = mkOption {
          type = types.int;
          default = 5672;
          description = "RabbitMQ port.";
        };

        virtualHost = mkOption {
          type = types.str;
          default = vpsadminCfg.rabbitmq.virtualHost;
          description = "RabbitMQ virtual host.";
        };

        username = mkOption {
          type = types.str;
          description = "RabbitMQ user name.";
        };

        passwordFile = mkOption {
          type = types.str;
          description = "Path to file containing RabbitMQ password.";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    vpsadmin = {
      enableOverlay = true;
      enableStateDirectory = true;
    };

    networking.firewall.extraCommands = concatStringsSep "\n" (
      (map (ip: ''
        iptables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString cfg.port} -j nixos-fw-accept
      '') cfg.allowedIPv4Ranges)
      ++ (map (ip: ''
        ip6tables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString cfg.port} -j nixos-fw-accept
      '') cfg.allowedIPv6Ranges)
    );

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDirectory}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/config' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.vpsadmin-vnc-router = {
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      preStart = ''
        RABBITMQ_PASS=$(head -n1 ${cfg.rabbitmq.passwordFile})
        RABBITMQ_URL="${cfg.rabbitmq.scheme}://${cfg.rabbitmq.username}:$RABBITMQ_PASS@${cfg.rabbitmq.host}:${toString cfg.rabbitmq.port}/${rabbitmqVhost}"
        escaped_url=$(printf '%s' "$RABBITMQ_URL" | sed -e 's|\\|\\\\|g' -e 's|&|\\&|g')
        cp -f ${configJson} "${cfg.stateDirectory}/config/config.json"
        sed -e "s|#rabbitmq_url#|$escaped_url|g" -i "${cfg.stateDirectory}/config/config.json"
        chmod 440 "${cfg.stateDirectory}/config/config.json"
      '';

      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = cfg.stateDirectory;
        ExecStart = "${cfg.package}/bin/vnc_router -config ${cfg.stateDirectory}/config/config.json${optionalString cfg.debug " -debug"}";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };

    users.users = optionalAttrs (cfg.user == "vpsadmin-vnc") {
      ${cfg.user} = {
        group = cfg.group;
        home = cfg.stateDirectory;
        isSystemUser = true;
      };
    };

    users.groups = optionalAttrs (cfg.group == "vpsadmin-vnc") {
      ${cfg.group} = { };
    };
  };
}
