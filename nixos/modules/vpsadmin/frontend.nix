{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.frontend;

  appOpt = app:
    mkOption {
      type = types.attrsOf (types.submodule (appModule app));
      default = {};
      description = ''
        Frontends to the vpsAdmin ${app} using nginx

        A frontend is a public server, usually with SSL, which serves
        as a reverse proxy to HAProxy. See <option>vpsadmin.haproxy.${app}</option>.

        To enable the SSL or to set any other nginx settings, access the nginx
        virtual host using its options,
        i.e. <option>services.nginx.virtualHost</option>.
      '';
    };

  appModule =
    app:
    { config, ... }:
    {
      options = {
        domain = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Public domain";
        };

        virtualHost = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = ''
            nginx virtual host name, see <option>services.nginx.virtualHosts</option>

            If not given, it defaults to the value of
            <option>vpsadmin.frontend.${app}.domain</option>.
          '';
          apply = v:
            if !isNull v then
              v
            else if !isNull config.domain then
              config.domain
            else
              abort "unable to determine virtual host name: set domain or virtualHost";
        };

        backend = {
          host = mkOption {
            type = types.str;
            description = ''
              Hostname or IP address of the backend, usually a HAProxy instance
            '';
          };

          port = mkOption {
            type = types.int;
            description = ''
              Port number of the backend, usually a HAProxy instance
            '';
          };
        };
      };
    };

  appVirtualHosts = app: name: instance: nameValuePair instance.virtualHost {
    serverName = mkIf (!isNull instance.domain) instance.domain;
    locations."/".proxyPass = "http://${instance.backend.host}:${toString instance.backend.port}";
  };

  appConfigs = app:
    let
      instances = cfg.${app};
    in {
      services.nginx.virtualHosts = mapAttrs' (appVirtualHosts app) instances;
    };

in {
  options = {
    vpsadmin.frontend = {
      enable = mkEnableOption "Enable vpsAdmin frontend reverse proxy";

      api = appOpt "api";

      webui = appOpt "webui";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      networking = {
        firewall.allowedTCPPorts = [
          80 443
        ];
      };

      services.nginx = {
        enable = true;

        recommendedGzipSettings = mkDefault true;
        recommendedOptimisation = mkDefault true;
        recommendedProxySettings = mkDefault true;
        recommendedTlsSettings = mkDefault true;
      };
    }

    (appConfigs "api")

    (appConfigs "webui")
  ]);
}
