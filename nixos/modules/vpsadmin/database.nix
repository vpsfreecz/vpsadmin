{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.database;
in {
  options = {
    vpsadmin = {
      database = {
        enable = mkEnableOption "Enable vpsAdmin database server";

        defaultConfig = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Apply default configuration
          '';
        };
      };
    };
  };

  config = mkIf cfg.enable {
    services.mysql = {
      enable = true;
      package = pkgs.mariadb;
      ensureDatabases = mkIf cfg.defaultConfig [ "vpsadmin" ];
      ensureUsers = mkIf cfg.defaultConfig [
        {
          name = "vpsadmin";
          ensurePermissions = {
            "vpsadmin.*" = "ALL PRIVILEGES";
          };
        }
      ];
    };
  };
}
