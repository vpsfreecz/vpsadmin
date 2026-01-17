{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.vpsadmin;
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
    nixpkgs.overlays = optionals cfg.enableOverlay (import ../../overlays);

    systemd.tmpfiles.rules = mkIf cfg.enableStateDirectory [
      "d /run/vpsadmin - - - - -"
      "d ${cfg.stateDirectory} - - - - -"
    ];
  };
}
