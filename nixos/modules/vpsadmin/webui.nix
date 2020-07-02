{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.webui;
  app = "vpsadmin-webui";
  boolToPhp = v: if v then "true" else "false";
in {
  options = {
    vpsadmin.webui = {
      enable = mkEnableOption "Enable vpsAdmin web interface";

      domain = mkOption {
        type = types.str;
      };

      dataDir = mkOption {
        type = types.str;
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
      };
    };
  };

  config = mkIf cfg.enable {
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
      phpEnv."PATH" = lib.makeBinPath [ pkgs.php ];
    };

    services.nginx = {
      enable = true;
      virtualHosts.${cfg.domain} = {
        root = cfg.dataDir;

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
      createHome = true;
      home = cfg.dataDir;
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

      define ('WWW_ROOT', '${cfg.dataDir}/');

      ${cfg.extraConfig}
    '';
  };
}
