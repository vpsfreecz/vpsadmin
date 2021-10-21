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

  baseOpts = app: config: {
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

      address = mkOption {
        type = types.str;
        default = "${config.backend.host}:${toString config.backend.port}";
        description = ''
          Upstream address string
        '';
      };
    };
  };

  baseModule =
    app:
    { config, ... }:
    let
      opts = baseOpts app config;
    in {
      options = {
        inherit (opts) domain virtualHost maintenance backend;
      };
    };

  downloadMounterModule =
    app:
    { config, ... }:
    let
      opts = baseOpts app config;
    in {
      options = {
        inherit (opts) domain virtualHost maintenance;
      };
    };

  appModule = app: {
    api = baseModule app;

    console-router = baseModule app;

    download-mounter = downloadMounterModule app;

    webui = baseModule app;
  }.${app};

  appMaintenances =
    let
      html = pkgs.writeText "maintenance.html" ''
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

      json = pkgs.writeText
        "maintenance.json"
        ''{"status":false,"message":"Server under maintenance."}'';
    in {
      api = json;

      console-router = html;

      download-mounter = html;

      webui = html;
    };

  isUnderMaintenance = app: name: instance:
    instance.maintenance.enable || (
      cfg.maintenance.enable && (
        isNull cfg.maintenance.frontends || elem name cfg.maintenance.frontends
      )
    );

  upstreamName = app: name: "${app}_${name}";

  baseUpstreams = app: instances: mapAttrs' (name: instance:
    nameValuePair (upstreamName app name) {
      servers = {
        "${instance.backend.address}" = {};
      };
    }
  ) instances;

  appUpstreams = app: instances: {
    api = baseUpstreams app instances;

    console-router = baseUpstreams app instances;

    download-mounter = {};

    webui = baseUpstreams app instances;
  }.${app};

  baseVirtualHosts = app: name: instance: nameValuePair instance.virtualHost {
    serverName = mkIf (!isNull instance.domain) instance.domain;

    forceSSL = mkIf (!isNull cfg.forceSSL) cfg.forceSSL;

    enableACME = mkIf (!isNull cfg.enableACME) cfg.enableACME;

    locations = {
      "/" = {
        proxyPass = mkIf (!isUnderMaintenance app name instance)
          "http://${upstreamName app name}";

        return = mkIf (isUnderMaintenance app name instance) "503";
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

  downloadMounterVirtualHosts = app: name: instance: nameValuePair instance.virtualHost {
    forceSSL = mkIf (!isNull cfg.forceSSL) cfg.forceSSL;

    enableACME = mkIf (!isNull cfg.enableACME) cfg.enableACME;

    locations = {
      "/" = mkIf config.vpsadmin.download-mounter.enable {
        root = config.vpsadmin.download-mounter.mountpoint;
        return = mkIf (isUnderMaintenance app name instance) "503";
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

  appVirtualHosts = app: {
    api = baseVirtualHosts app;

    console-router = baseVirtualHosts app;

    download-mounter = downloadMounterVirtualHosts app;

    webui = baseVirtualHosts app;
  }.${app};

  appAssertions = app: instances: {
    api = [];

    console-router = [];

    download-mounter = [
      {
        assertion = instances != {} -> config.vpsadmin.download-mounter.enable;
        message = "vpsadmin.frontend.download-mounter requires vpsadmin.download-mounter to be enabled";
      }
    ];

    webui = [];
  }.${app};

  appConfigs = app:
    let
      instances = cfg.${app};
    in {
      assertions = appAssertions app instances;

      services.nginx = {
        upstreams = appUpstreams app instances;

        virtualHosts = mapAttrs' (appVirtualHosts app) instances;
      };
    };

in {
  options = {
    vpsadmin.frontend = {
      enable = mkEnableOption "Enable vpsAdmin frontend reverse proxy";

      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Open ports 80 and 443 in the firewall
        '';
      };

      maintenance = {
        enable = mkEnableOption ''
          Enable maintenance on all frontends

          Frontends can be further selected using option
          <option>vpsadmin.frontend.maintenance.frontends</option>.
        '';

        frontends = mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          description = ''
            List of frontend names to put under maintenance
          '';
        };
      };

      forceSSL = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Shortcut to set <option>services.nginx.virtualHosts.&lt;name&gt;.forceSSL</option>
          on all frontends
        '';
      };

      enableACME = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = ''
          Shortcut to set <option>services.nginx.virtualHosts.&lt;name&gt;.enableACME</option>
          on all frontends
        '';
      };

      api = appOpt "api";

      console-router = appOpt "console-router";

      download-mounter = appOpt "download-mounter";

      webui = appOpt "webui";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      networking = {
        firewall.allowedTCPPorts = mkIf cfg.openFirewall [
          80 443
        ];
      };

      # This is to enable mount propagation from the host ns to systemd services,
      # e.g. nginx. At least in vpsAdminOS containers, the default mount
      # propagation mode seems to be `private`. That makes it impossible to
      # use the download mounter, because NFS mounts do not appear within
      # the nginx's mount namespace after it is created.
      boot.postBootCommands = ''
        mount --make-shared /
      '';

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

    (appConfigs "console-router")

    (appConfigs "download-mounter")

    (appConfigs "webui")
  ]);
}
