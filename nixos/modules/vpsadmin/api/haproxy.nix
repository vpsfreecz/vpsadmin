{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.api.haproxy;
  apiCfg = config.vpsadmin.api;

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

  backendsConfig = imap0 (i: backend:
    "  server app${toString i} ${backend.host}:${toString backend.port} check"
  ) cfg.backends;
in {
  options = {
    vpsadmin.api.haproxy = {
      enable = mkEnableOption "Enable haproxy for vpsAdmin API";

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
      };

      backends = mkOption {
        type = types.listOf (types.submodule backendOpts);
        description = ''
          List of vpsAdmin API backends
        '';
      };
    };
  };

  config = mkIf cfg.enable {
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

        frontend api
          bind                    ${cfg.frontend.address}:${toString cfg.frontend.port}
          default_backend         app

        backend app
          balance     roundrobin
        ${concatStringsSep "\n" backendsConfig}
      '';
    };
  };
}
