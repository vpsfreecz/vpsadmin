{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.redis;
in {
  options = {
    vpsadmin.redis = {
      enable = mkEnableOption "Enable redis for vpsAdmin";

      passwordFile = mkOption {
        type = types.path;
        description = ''
          File with password to the database.

          Passed to <option>services.redis.requirePassFile</option>.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    services.redis = {
      enable = true;
      bind = null;
      requirePassFile = cfg.passwordFile;
    };
  };
}
