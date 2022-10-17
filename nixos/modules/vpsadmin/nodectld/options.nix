{ config, lib, pkgs, utils, ... }:
with lib;
let
  cfg = config.vpsadmin.nodectld;

  settingsFormat = pkgs.formats.yaml { };

  configurationYaml = settingsFormat.generate "nodectld.yml" cfg.settings;
in {
  options = {
    vpsadmin.nodectld = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable vpsAdmin integration, i.e. include nodectld and nodectl
        '';
      };

      settings = mkOption {
        type = types.submodule {
          freeformType = settingsFormat.type;
        };
        default = {};
        description = ''
          nodectld configuration options
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    environment.etc."vpsadmin/nodectld.yml".source = configurationYaml;
  };
}
