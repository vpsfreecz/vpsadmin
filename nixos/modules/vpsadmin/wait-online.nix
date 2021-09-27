{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.waitOnline;

  waitForApiService = "vpsadmin-api-wait-online";

  waitForApi = pkgs.writeScript "${waitForApiService}.sh" ''
    #!${pkgs.bash}/bin/bash
    echo -n api-wait-online > /proc/$$/comm
    while true ; do
      ${pkgs.curl}/bin/curl "${cfg.api.url}" >/dev/null 2>&1 && exit 0
      sleep 1
    done
  '';
in {
  options = {
    vpsadmin.waitOnline = {
      api = {
        enable = mkEnableOption "Enable the vpsadmin-api-wait-online service";

        url = mkOption {
          type = types.str;
          description = "URL of the API server";
        };

        service = mkOption {
          type = types.str;
          description = "systemd service name";
          default = "${waitForApiService}.service";
          readOnly = true;
        };
      };
    };
  };

  config = {
    systemd.services.${waitForApiService} = mkIf cfg.api.enable {
      description = "Wait until the API server starts to respond";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = "yes";
        TimeoutSec = "5m";
        ExecStart = waitForApi;
      };
    };
  };
}
