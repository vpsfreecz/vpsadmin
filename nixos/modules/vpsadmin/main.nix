{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin;
in {
  options = {
    vpsadmin = {
      enableOverlay = mkOption {
        type = types.bool;
        default = false;
      };

      enableStateDir = mkOption {
        type = types.bool;
        default = false;
      };

      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/vpsadmin";
      };
    };
  };

  config = {
    nixpkgs.overlays = mkIf cfg.enableOverlay (import ../../overlays);

    systemd.tmpfiles.rules = mkIf cfg.enableStateDir [
      "d /run/vpsadmin - - - - -"
      "d ${cfg.stateDir} - - - - -"
    ];
  };
}
