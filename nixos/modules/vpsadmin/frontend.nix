{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.frontend;

  anyApp = cfg.api.enable || cfg.webui.enable;

  appOpts =
    app:
    { config, ... }:
    {
      options = {
        enable = mkEnableOption ''
          Enable frontend to the vpsAdmin ${app} using nginx

          The frontend is a public server, usually with SSL, which serves
          as a reverse proxy to HAProxy. See <option>vpsadmin.haproxy.${app}</option>.

          To enable the SSL or to set any other nginx settings, access the nginx
          virtual host using its options,
          i.e. <option>services.nginx.virtualHost</option>.
        '';

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
              abort "unable to determine virtual host name";
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

  appConfig = app:
    let
      appCfg = cfg.${app};
    in {
      assertions = [
        {
          assertion = (!isNull appCfg.domain) || (!isNull appCfg.virtualHost);
          message = "Set vpsadmin.frontend.${app}.domain or virtualHost";
        }
      ];

      services.nginx.virtualHosts.${appCfg.virtualHost} = {
        serverName = mkIf (!isNull appCfg.domain) appCfg.domain;
        locations."/".proxyPass = "http://${appCfg.backend.host}:${toString appCfg.backend.port}";
      };
    };
in {
  options = {
    vpsadmin.frontend = {
      enable = mkEnableOption "Enable vpsAdmin frontend reverse proxy";

      api = mkOption {
        type = types.submodule (appOpts "api");
        default = {};
      };

      webui = mkOption {
        type = types.submodule (appOpts "webui");
        default = {};
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = anyApp;
          message = "Enable at least one component in vpsadmin.frontend";
        }
      ];

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

    (mkIf cfg.api.enable (appConfig "api"))

    (mkIf cfg.webui.enable (appConfig "webui"))
  ]);
}
