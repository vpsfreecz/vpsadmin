{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.download-mounter;

  bundle = "${cfg.package}/ruby-env/bin/bundle";
in {
  options = {
    vpsadmin.download-mounter = {
      enable = mkEnableOption "Enable vpsAdmin download mounter service";

      package = mkOption {
        type = types.package;
        default = pkgs.vpsadmin-download-mounter;
        description = "Which vpsAdmin download mounter package to use.";
        example = "pkgs.vpsadmin-download-mounter.override { ruby = pkgs.ruby_3_1; }";
      };

      api.url = mkOption {
        type = types.str;
        description = "URL to the API server.";
      };

      api.tokenFile = mkOption {
        type = types.str;
        description = "A file containing authentication token to the API.";
      };

      mountpoint = mkOption {
        type = types.str;
        description = ''
          Directory where the download directories from all nodes will be mounted.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    vpsadmin = {
      enableOverlay = true;
      waitOnline.api = {
        enable = true;
        url = cfg.api.url;
      };
    };

    boot.supportedFilesystems = [ "nfs" ];

    systemd.services.vpsadmin-download-mounter = {
      description = "Mount download directories from vpsAdmin nodes";
      after = [ "network.target" config.vpsadmin.waitOnline.api.service ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        nfs-utils
        utillinux
      ];
      serviceConfig =
        let
          mounterCommand = cmd: toString ([
            "${bundle}" "exec"
            "bin/vpsadmin-download-mounter"
            "--auth" "token"
            "--load-token" cfg.api.tokenFile
            cfg.api.url
            cfg.mountpoint
          ] ++ [ cmd ]);
        in {
          Type = "oneshot";
          TimeoutSec = "900";
          WorkingDirectory = "${cfg.package}/download_mounter";
          ExecStart = mounterCommand "mount";
        };
    };

    systemd.timers.vpsadmin-download-mounter = {
      description = "Periodically mount download directories";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnUnitInactiveSec = "15m";
      };
    };
  };
}
