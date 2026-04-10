{
  config,
  pkgs,
  lib,
  vpsadminos ? null,
  vpsadminRev,
  ...
}:
with lib;
let
  cfg = config.vpsadmin;
  jsonFormat = pkgs.formats.json { };
  vpsadminosPath =
    if vpsadminos == null then
      null
    else if builtins.isAttrs vpsadminos && vpsadminos ? outPath then
      vpsadminos.outPath
    else
      vpsadminos;
  vpsadminosRubyOverlay =
    if vpsadminosPath == null then null else import (vpsadminosPath + "/os/overlays/ruby.nix");
  overlayList = import ../../overlays { inherit vpsadminRev; };
in
{
  options = {
    vpsadmin = {
      enableOverlay = mkOption {
        type = types.bool;
        default = false;
      };

      enableStateDirectory = mkOption {
        type = types.bool;
        default = false;
      };

      stateDirectory = mkOption {
        type = types.str;
        default = "/var/lib/vpsadmin";
      };

      plugins = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of plugins to enable.";
      };

      deploymentConfig = mkOption {
        type = jsonFormat.type;
        default = { };
        description = ''
          Generic deployment configuration rendered to `deployment.json` for
          vpsAdmin API-based services.
        '';
      };

      rabbitmq = {
        hosts = mkOption {
          type = types.listOf types.str;
          description = ''
            A list of rabbitmq hosts to connect to
          '';
        };

        virtualHost = mkOption {
          type = types.str;
          default = "/";
          description = ''
            rabbitmq virtual host
          '';
        };
      };
    };
  };

  config = {
    nixpkgs.overlays = optionals cfg.enableOverlay (
      assert lib.assertMsg (
        vpsadminosRubyOverlay != null
      ) "vpsadminos is required to enable vpsadmin overlays";
      [ vpsadminosRubyOverlay ] ++ overlayList
    );

    systemd.tmpfiles.rules = mkIf cfg.enableStateDirectory [
      "d /run/vpsadmin - - - - -"
      "d ${cfg.stateDirectory} - - - - -"
    ];
  };
}
