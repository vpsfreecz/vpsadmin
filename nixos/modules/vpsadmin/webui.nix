{ config, pkgs, lib, ... }:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.webui;
  app = "vpsadmin-webui";
  boolToPhp = v: if v then "true" else "false";
  rootDir =
    if isNull cfg.sourceCodeDir then
      cfg.package
    else
      cfg.sourceCodeDir;
in {
  options = {
    vpsadmin.webui = {
      enable = mkEnableOption "Enable vpsAdmin web interface";

      domain = mkOption {
        type = types.str;
      };

      package = mkOption {
        default = pkgs.vpsadmin-webui pkgs;
        description = "Which vpsAdmin webui package to use";
      };

      sourceCodeDir = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          Instead of the packaged app, run it from the source code mounted at
          a configured path
        '';
      };

      stateDir = mkOption {
        type = types.str;
        default = "${vpsadminCfg.stateDir}/webui";
        description = "The state directory";
      };

      timeZone = mkOption {
        type = types.str;
        description = ''
          Time zone, defaults to the system time zone

          See https://www.php.net/manual/en/timezones.php
        '';
      };

      api.externalUrl = mkOption {
        type = types.str;
        description = ''
          URL to the API server that must be accessible from the outside, as it
          is passed to the client.
        '';
      };

      api.internalUrl = mkOption {
        type = types.str;
        description = ''
          URL to the API server which is used internally,
          i.e. from the server-side.
        '';
      };

      productionEnvironmentId = mkOption {
        type = types.int;
        description = ''
          ID of the production environment
        '';
      };

      usernsPublic = mkOption {
        type = types.bool;
        default = false;
      };

      exportPublic = mkOption {
        type = types.bool;
        default = true;
      };

      nasPublic = mkOption {
        type = types.bool;
        default = true;
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Lines appended to /etc/vpsadmin/config.php

          Note that in order to run multiple instances of the web UI, you need
          to configure access to redis for session handling. Since connecting
          to redis requires a password, it cannot be done from Nix configuration.
          Instead, use this option to require a hidden file which configures
          access to redis, e.g.

          <literal>
          require "/secret/vpsadmin-webui.config.php";
          </literal>

          and the file would contain the following:

          <literal>
          <?php
          ini_set("session.save_handler", "redis");
          ini_set("session.save_path", "tcp://1.2.3.4:6379?auth=your-password");
          </literal>
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
    vpsadmin = {
      enableOverlay = true;
      enableStateDir = true;
      webui.timeZone = mkDefault config.time.timeZone;
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0750 ${app} ${app} - -"
    ];

    services.phpfpm.pools.${app} = {
      user = app;
      settings = {
        "listen.owner" = config.services.nginx.user;
        "pm" = "dynamic";
        "pm.max_children" = 32;
        "pm.max_requests" = 500;
        "pm.start_servers" = 2;
        "pm.min_spare_servers" = 2;
        "pm.max_spare_servers" = 5;
        "php_admin_value[error_log]" = "stderr";
        "php_admin_flag[log_errors]" = true;
        "catch_workers_output" = true;
      };
      phpEnv."PATH" = lib.makeBinPath (with pkgs; [ git php ]);
      phpOptions = ''
        date.timezone = ${cfg.timeZone}
        extension=${pkgs.phpExtensions.json}/lib/php/extensions/json.so
        extension=${pkgs.phpExtensions.session}/lib/php/extensions/session.so
        extension=${pkgs.phpExtensions.redis}/lib/php/extensions/redis.so
      '';
    };

    networking.firewall.extraCommands = concatStringsSep "\n" (
      (map (ip: ''
        iptables -A nixos-fw -p tcp -m tcp -s ${ip} --dport 80 -j nixos-fw-accept
      '') cfg.allowedIPv4Ranges)
      ++
      (map (ip: ''
        ip6tables -A nixos-fw -p tcp -m tcp -s ${ip} --dport 80 -j nixos-fw-accept
      '') cfg.allowedIPv6Ranges)
    );

    services.nginx = {
      enable = true;
      virtualHosts.${cfg.domain} = {
        root = rootDir;

        locations."~* .php$".extraConfig = ''
          fastcgi_split_path_info ^(.+\.php)(/.+)$;
          fastcgi_pass unix:${config.services.phpfpm.pools.${app}.socket};
          include ${pkgs.nginx}/conf/fastcgi_params;
          include ${pkgs.nginx}/conf/fastcgi.conf;

          fastcgi_index index.php;
          fastcgi_connect_timeout 60;
          fastcgi_send_timeout 180;
          fastcgi_read_timeout 180;
          fastcgi_buffer_size 128k;
          fastcgi_buffers 4 256k;
          fastcgi_busy_buffers_size 256k;
          fastcgi_temp_file_write_size 256k;
        '';

        # Deny access to hidden files
        locations."~ /\\.".extraConfig = ''
          deny all;
          access_log off;
          log_not_found off;
        '';

        extraConfig = ''
          autoindex off;
          index index.php;

          client_max_body_size 15m;
          client_body_buffer_size 128k;
        '';
      };
    };

    users.users.${app} = {
      isSystemUser = true;
      home = cfg.stateDir;
      group = app;
    };
    users.groups.${app} = {};

    environment.etc."vpsadmin/config.php".text = ''
      <?php
      define ('EXT_API_URL', '${cfg.api.externalUrl}');
      define ('INT_API_URL', '${cfg.api.internalUrl}');
      define ('ENV_VPS_PRODUCTION_ID', ${toString cfg.productionEnvironmentId});

      define ('PRIV_POORUSER', 1);
      define ('PRIV_USER', 2);
      define ('PRIV_POWERUSER', 3);
      define ('PRIV_ADMIN', 21);
      define ('PRIV_SUPERADMIN', 90);
      define ('PRIV_GOD', 99);

      define ('USERNS_PUBLIC', ${boolToPhp cfg.usernsPublic});
      define ('EXPORT_PUBLIC', ${boolToPhp cfg.exportPublic});
      define ('NAS_PUBLIC', ${boolToPhp cfg.nasPublic});

      define ('WWW_ROOT', '${rootDir}/');

      ${cfg.extraConfig}
    '';
  };
}
