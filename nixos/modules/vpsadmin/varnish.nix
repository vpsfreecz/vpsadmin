{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib)
    concatStringsSep
    filterAttrs
    mapAttrsToList
    mkEnableOption
    mkIf
    mkOption
    optionalString
    types
    ;

  cfg = config.vpsadmin.varnish;
  apiCfg = config.vpsadmin.varnish;

  appOpts =
    { config, ... }:
    {
      options = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Enable this virtual host
          '';
        };

        domain = mkOption {
          type = types.str;
          description = ''
            Virtual host name
          '';
        };

        backend = {
          host = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Hostname or IP address
            '';
          };

          port = mkOption {
            type = types.nullOr types.int;
            default = null;
            description = ''
              Port number
            '';
          };

          path = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Path to UNIX socket
            '';
          };
        };
      };
    };

  enabledVhosts = vhosts: filterAttrs (name: vhost: vhost.enable) vhosts;

  appBackendDefs =
    app: vhosts:
    concatStringsSep "\n" (
      mapAttrsToList (name: vhost: ''
        backend ${app}_${name} {
          ${optionalString (!isNull vhost.backend.host) ".host = \"${vhost.backend.host}\";"}
          ${optionalString (!isNull vhost.backend.port) ".port = \"${toString vhost.backend.port}\";"}
          ${optionalString (!isNull vhost.backend.path) ".path = \"${vhost.backend.path}\";"}
        }
      '') (enabledVhosts vhosts)
    );

  apiVclRecv =
    vhosts:
    concatStringsSep "\n" (
      mapAttrsToList (name: vhost: ''
        if (req.http.host == "${vhost.domain}") {
          set req.backend_hint = api_${name};

          if (req.url !~ "^/metrics\?") {
            return(pass);
          }
        }
      '') (enabledVhosts vhosts)
    );

  apiVclBackendResponse =
    vhosts:
    concatStringsSep "\n" (
      mapAttrsToList (name: vhost: ''
        if (bereq.http.host == "${vhost.domain}") {
          if (bereq.url ~ "^/metrics\?") {
            set beresp.ttl = 60s;
          }
        }
      '') (enabledVhosts vhosts)
    );

  varnishConfig = ''
    vcl 4.1;

    ${appBackendDefs "api" cfg.api}

    sub vcl_recv {
      ${apiVclRecv cfg.api}
    }

    sub vcl_backend_response {
      ${apiVclBackendResponse cfg.api}
    }
  '';
in
{
  options = {
    vpsadmin.varnish = {
      enable = mkEnableOption "Enable Varnish for vpsAdmin";

      bind = {
        address = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = "
            Address, hostname or UNIX socket to listen on. Passed to Varnish command-line
            option `-a`. See also {option}`services.varnish.listen.address`.
          ";
        };

        port = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = ''
            Port to listen on. See also {option}`services.varnish.listen.port`.
          '';
        };

        mode = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            Permission of the socket file, see See also {option}`services.varnish.listen.mode`.
          '';
        };
      };

      api = mkOption {
        type = types.attrsOf (types.submodule appOpts);
        default = { };
        description = ''
          Virtual hosts for vpsAdmin API
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    services.varnish = {
      enable = true;
      listen = [ { inherit (cfg.bind) address port mode; } ];
      config = varnishConfig;
    };
  };
}
