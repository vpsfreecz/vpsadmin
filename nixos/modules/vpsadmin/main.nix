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
    nixpkgs.overlays = [
      (self: super: { ruby = super.ruby_3_0; })
    ] ++ optionals cfg.enableOverlay (import ../../overlays);

    systemd.tmpfiles.rules = mkIf cfg.enableStateDir [
      "d /run/vpsadmin - - - - -"
      "d ${cfg.stateDir} - - - - -"
    ];
  };
}
