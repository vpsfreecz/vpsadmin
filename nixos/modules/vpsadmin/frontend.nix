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

        maintenance = {
          enable = mkEnableOption ''
            When enabled, the server responds with HTTP status 503 to all requests
          '';

          file = mkOption {
            type = types.path;
            default = appMaintenances.${app};
            description = ''
              File that is served when the maintenance is enabled
            '';
          };
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

  appMaintenances = {
    api = pkgs.writeText "maintenance.json" ''{"status":false,"message":"Server under maintenance."}'';

    webui = pkgs.writeText "maintenance.html" ''
      <!DOCTYPE html>
      <html>
      <head>
      <title>Maintenance</title>
      </head>
      <body>
      <h1>Ongoing maintenance</h1>
      <p>The server is under maintenance. Please try again later.</p>
      </body>
      </html>
    '';
  };

  appVirtualHosts = app: name: instance: nameValuePair instance.virtualHost {
    serverName = mkIf (!isNull instance.domain) instance.domain;

    locations = {
      "/" = {
        proxyPass = mkIf (!instance.maintenance.enable)
          "http://${instance.backend.host}:${toString instance.backend.port}";

        return = mkIf instance.maintenance.enable "503";
      };

      "@maintenance" = {
        root = pkgs.runCommand "${app}-maintenance-root" {} ''
          mkdir $out
          ln -s ${instance.maintenance.file} $out/${instance.maintenance.file.name}
        '';
        extraConfig = ''
          rewrite ^(.*)$ /${instance.maintenance.file.name} break;
        '';
      };
    };

    extraConfig = ''
      error_page 503 @maintenance;
    '';
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

        appendHttpConfig = ''
          server_names_hash_bucket_size 64;
        '';
      };
    }

    (appConfigs "api")

    (appConfigs "webui")
  ]);
}
