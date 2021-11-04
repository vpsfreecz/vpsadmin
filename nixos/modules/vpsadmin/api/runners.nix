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

  apiRubyRunner = pkgs.writeScript "vpsadmin-api-ruby-runner" ''
    #!${pkgs.ruby}/bin/ruby

    if ARGV.length < 1
      warn "Usage: #{$0} <script> [args...]"
      exit(false)
    end

    $: << "${cfg.package}/api/lib"
    script = ARGV[0]
    ARGV.shift
    load script
  '';

  apiRubyScript = pkgs.writeScriptBin "vpsadmin-api-ruby" ''
    #!${pkgs.bash}/bin/bash

    if [ "$1" == "" ] ; then
      echo "Usage: $0 <script> [args...]"
      exit 1
    fi

    SCRIPT="$(realpath "$1")"
    shift

    exec systemd-run \
      --unit=vpsadmin-api-ruby-$(date "+%F-%T") \
      --description="vpsAdmin API ruby script" \
      --pty \
      --wait \
      --collect \
      --service-type=exec \
      --working-directory=${cfg.package}/api \
      --setenv=RACK_ENV=production \
      --setenv=SCHEMA=${cfg.stateDir}/cache/structure.sql \
      --uid ${cfg.user} \
      --gid ${cfg.group} \
      ${bundle} exec ${apiRubyRunner} "$SCRIPT" $@
  '';
in {
  config = mkIf cfg.enable {
    environment.systemPackages = [
      apiShellScript
      apiRubyScript
    ];
  };
}
