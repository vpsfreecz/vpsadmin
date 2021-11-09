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
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Enable this application instance in HAProxy
          '';
        };

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
            type = types.nullOr (types.listOf types.str);
            default = null;
            description = ''
              HAProxy bind directive
            '';
            apply = v:
              if isNull v then
                [ "${config.address}:${toString config.port}" ]
              else v;
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

  allAppAssertions =
    (appAssertions "api")
    ++
    (appAssertions "console-router")
    ++
    (appAssertions "webui");

  appAssertions = app:
    mapAttrsToList (name: instance: {
      assertion = instance.enable -> (instance.frontend.bind != []);
      message = "Add at least one item to vpsadmin.haproxy.${app}.${name}.frontend.bind";
    }) cfg.${app};

  backendsConfig = backends:
    imap0 (i: backend:
      "  server app${toString i} ${backend.host}:${toString backend.port} check"
    ) backends;

  apiConfig = name: instance: ''
    frontend api-${name}
      ${concatMapStringsSep "\n" (v: "bind ${v}") instance.frontend.bind}
      default_backend app-api-${name}

    backend app-api-${name}
      balance roundrobin
    ${concatStringsSep "\n" (backendsConfig instance.backends)}
  '';

  consoleRouterConfig = name: instance: ''
    frontend console-router-${name}
      ${concatMapStringsSep "\n" (v: "bind ${v}") instance.frontend.bind}
      default_backend app-console-router-${name}

    backend app-console-router-${name}
      balance hdr(X-Forwarded-For)
    ${concatStringsSep "\n" (backendsConfig instance.backends)}
  '';

  webuiConfig = name: instance: ''
    frontend webui-${name}
      ${concatMapStringsSep "\n" (v: "bind ${v}") instance.frontend.bind}
      default_backend app-webui-${name}

    backend app-webui-${name}
      balance roundrobin
    ${concatStringsSep "\n" (backendsConfig instance.backends)}
  '';

  enabledInstances = instances: filterAttrs (name: instance:
    instance.enable
  ) instances;

  stringConfigs = instances: fn:
    concatStringsSep "\n\n" (mapAttrsToList fn (enabledInstances instances));
in {
  options = {
    vpsadmin.haproxy = {
      enable = mkEnableOption "Enable HAProxy for vpsAdmin";

      api = mkOption {
        type = types.attrsOf (types.submodule appOpts);
        default = {};
        description = ''
          HAProxy instances for vpsAdmin API
        '';
      };

      console-router = mkOption {
        type = types.attrsOf (types.submodule appOpts);
        default = {};
        description = ''
          HAProxy instances for vpsAdmin console router
        '';
      };

      webui = mkOption {
        type = types.attrsOf (types.submodule appOpts);
        default = {};
        description = ''
          HAProxy instances for vpsAdmin web UI
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = allAppAssertions;

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

        ${stringConfigs cfg.api apiConfig}
        ${stringConfigs cfg.console-router consoleRouterConfig}
        ${stringConfigs cfg.webui webuiConfig}
      '';
    };
  };
}
