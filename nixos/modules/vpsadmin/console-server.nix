{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkEnableOption mkIf;

  cfg = config.vpsadmin.console-server;
in
{
  options = {
    vpsadmin.console-server = {
      enable = mkEnableOption "Enable console server";
    };
  };

  config = mkIf cfg.enable {
    runit.services.console-server = {
      run = ''
        export HOME=${config.users.extraUsers.root.home}
        export LANG=en_US.UTF-8
        export LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive
        exec 2>&1
        exec ${pkgs.console_server}/bin/console-server
      '';

      log.enable = true;
      log.sendTo = "127.0.0.1";
    };

    environment.systemPackages = with pkgs; [
      console_client
      vmexec
    ];
  };
}
