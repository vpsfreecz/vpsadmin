{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.database;
in {
  options = {
    vpsadmin.database = {
      enable = mkEnableOption "Enable vpsAdmin database server";
    };
  };

  config = mkIf cfg.enable {
    services.mysql = {
      enable = true;
      package = pkgs.mariadb;
      ensureDatabases = [ "vpsadmin" ];
      ensureUsers = [
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
