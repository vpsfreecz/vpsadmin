name:
{ config, pkgs, lib, ... }:
with lib;
let
  cfg = config.vpsadmin.${name};

  bundle = "${cfg.package}/ruby-env/bin/bundle";

  shellRcFile = pkgs.writeText "vpsadmin-${name}-shell.rc" ''
    . /etc/profile
    export PATH=${cfg.package}/ruby-env/bin:${pkgs.mariadb}/bin:$PATH
  '';

  shellScript = pkgs.writeScriptBin "vpsadmin-${name}-shell" ''
    #!${pkgs.bash}/bin/bash
    exec systemd-run \
      --unit=vpsadmin-${name}-shell-$(date "+%F-%T") \
      --description="vpsAdmin ${name} interactive shell" \
      --pty \
      --wait \
      --collect \
      --service-type=exec \
      --working-directory=${cfg.package}/${name} \
      --setenv=RACK_ENV=production \
      --setenv=SCHEMA=${cfg.stateDirectory}/cache/structure.sql \
      --uid ${cfg.user} \
      --gid ${cfg.group} \
      ${pkgs.bashInteractive}/bin/bash --rcfile ${shellRcFile}
  '';

  rubyRunner = pkgs.writeScript "vpsadmin-${name}-ruby-runner" ''
    #!${pkgs.ruby}/bin/ruby

    if ARGV.length < 1
      warn "Usage: #{$0} <script> [args...]"
      exit(false)
    end

    $: << "${cfg.package}/${name}/lib"
    script = ARGV[0]
    ARGV.shift
    load script
  '';

  rubyScript = pkgs.writeScriptBin "vpsadmin-${name}-ruby" ''
    #!${pkgs.bash}/bin/bash

    if [ "$1" == "" ] ; then
      echo "Usage: $0 <script> [args...]"
      exit 1
    fi

    SCRIPT="$(realpath "$1")"
    shift

    exec systemd-run \
      --unit=vpsadmin-${name}-ruby-$(date "+%F-%T") \
      --description="vpsAdmin ${name} ruby script" \
      --pty \
      --wait \
      --collect \
      --service-type=exec \
      --working-directory=${cfg.package}/${name} \
      --setenv=RACK_ENV=production \
      --setenv=SCHEMA=${cfg.stateDirectory}/cache/structure.sql \
      --uid ${cfg.user} \
      --gid ${cfg.group} \
      ${bundle} exec ${rubyRunner} "$SCRIPT" $@
  '';
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [
      shellScript
      rubyScript
    ];
  };
}
