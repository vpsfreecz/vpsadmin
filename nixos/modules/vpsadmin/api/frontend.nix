{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.api.frontend;
in {
  options = {
    vpsadmin.api.frontend = {
      enable = mkEnableOption ''
        Enable frontend to the vpsAdmin API using nginx

        The frontend is a public server, usually with SSL, which serves
        as a reverse proxy to HAProxy. See <option>vpsadmin.haproxy.api</option>.

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
        '';
        apply = v:
          if !isNull v then
            v
          else if !isNull cfg.domain then
            cfg.domain
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

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (!isNull cfg.domain) || (!isNull cfg.virtualHost);
        message = "Set vpsadmin.api.frontend.domain or virtualHost";
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

      virtualHosts.${cfg.virtualHost} = {
        serverName = mkIf (!isNull cfg.domain) cfg.domain;
        locations."/".proxyPass = "http://${cfg.backend.host}:${toString cfg.backend.port}";
      };
    };
  };
}
