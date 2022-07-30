{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.vpsadmin.nodectld;
in {
  imports = [
    ./options.nix
  ];

  config = mkIf cfg.enable {
    nixpkgs.overlays = import ../../../overlays;

    boot.postBootCommands = ''
      mkdir -m 0700 /run/nodectl
      ln -sfn /run/current-system/sw/bin/nodectl /run/nodectl/nodectl
    '';

    runit.services.nodectld = {
      run = ''
        ulimit -c unlimited
        export HOME=${config.users.extraUsers.root.home}
        exec 2>&1
        exec ${pkgs.nodectld}/bin/nodectld --log syslog --log-facility local3 --export-console
      '';
      killMode = "process";
    };

    environment.systemPackages = with pkgs; [
      mbuffer
      nodectl
    ];
  };
}
