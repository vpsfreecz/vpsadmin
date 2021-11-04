{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.api;

  bundle = "${cfg.package}/ruby-env/bin/bundle";

  apiShellRcFile = pkgs.writeText "vpsadmin-api-shell.rc" ''
    . /etc/profile
    export PATH=${cfg.package}/ruby-env/bin:$PATH
  '';

  apiShellScript = pkgs.writeScriptBin "vpsadmin-api-shell" ''
    #!${pkgs.bash}/bin/bash
    exec systemd-run \
      --unit=vpsadmin-api-shell-$(date "+%F-%T") \
      --description="vpsAdmin API interactive shell" \
      --pty \
      --wait \
      --collect \
      --service-type=exec \
      --working-directory=${cfg.package}/api \
      --setenv=RACK_ENV=production \
      --setenv=SCHEMA=${cfg.stateDir}/cache/structure.sql \
      --uid ${cfg.user} \
      --gid ${cfg.group} \
      ${pkgs.bashInteractive}/bin/bash --rcfile ${apiShellRcFile}
  '';
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [
      apiShellScript
    ];
  };
}
