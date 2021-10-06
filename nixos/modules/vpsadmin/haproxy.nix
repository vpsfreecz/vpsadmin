{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.haproxy;
  apiCfg = config.vpsadmin.haproxy;

  backendOpts =
    { config, ... }:
    {
      options = {
        host = mkOption {
          type = types.str;
          description = ''
            Hostname or IP address
          '';
        };

        port = mkOption {
          type = types.int;
          description = ''
            Port number
          '';
        };
      };
    };

  appOpts =
    { config, ... }:
    {
      options = {
        enable = mkEnableOption "Enable HAProxy for the application";

        frontend = {
          address = mkOption {
            type = types.str;
            default = "*";
            description = ''
              Address to listen on
            '';
          };

          port = mkOption {
            type = types.int;
            default = 5000;
            description = ''
              Port to access the frontend
            '';
          };

          bind = mkOption {
            type = types.str;
            default = "${config.address}:${toString config.port}";
            description = ''
              HAProxy bind directive
            '';
          };
        };

        backends = mkOption {
          type = types.listOf (types.submodule backendOpts);
          description = ''
            List of backend servers
          '';
        };
      };
    };

  backendsConfig = backends:
    imap0 (i: backend:
      "  server app${toString i} ${backend.host}:${toString backend.port} check"
    ) backends;

  apiConfig = ''
    frontend api
      bind ${cfg.api.frontend.bind}
      default_backend app-api

    backend app-api
      balance roundrobin
    ${concatStringsSep "\n" (backendsConfig cfg.api.backends)}
  '';

  consoleRouterConfig = ''
    frontend console-router
      bind ${cfg.console-router.frontend.bind}
      default_backend app-console-router

    backend app-console-router
      balance hdr(X-Forwarded-For)
    ${concatStringsSep "\n" (backendsConfig cfg.console-router.backends)}
  '';

  webuiConfig = ''
    frontend webui
      bind ${cfg.webui.frontend.bind}
      default_backend app-webui

    backend app-webui
      balance roundrobin
    ${concatStringsSep "\n" (backendsConfig cfg.webui.backends)}
  '';
in {
  options = {
    vpsadmin.haproxy = {
      enable = mkEnableOption "Enable HAProxy for vpsAdmin";

      api = mkOption {
        type = types.submodule appOpts;
        default = {};
        description = ''
          HAProxy for vpsAdmin API
        '';
      };

      console-router = mkOption {
        type = types.submodule appOpts;
        default = {};
        description = ''
          HAProxy for vpsAdmin console router
        '';
      };

      webui = mkOption {
        type = types.submodule appOpts;
        default = {};
        description = ''
          HAProxy for vpsAdmin web UI
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.api.enable || cfg.console-router.enable || cfg.webui.enable;
        message = "Enable at least one of vpsadmin.haproxy.api, console-router or webui";
      }
    ];

    services.haproxy = {
      enable = true;
      config = ''
        global
          log stdout format short daemon
          maxconn     4000

        defaults
          mode                    http
          log                     global
          option                  httplog
          option                  dontlognull
          option http-server-close
          option forwardfor       except 127.0.0.0/8
          option                  redispatch
          retries                 3
          timeout http-request    10s
          timeout queue           1m
          timeout connect         10s
          timeout client          1m
          timeout server          1m
          timeout http-keep-alive 10s
          timeout check           10s
          maxconn                 3000

        ${optionalString cfg.api.enable apiConfig}
        ${optionalString cfg.console-router.enable consoleRouterConfig}
        ${optionalString cfg.webui.enable webuiConfig}
      '';
    };
  };
}
