{
  config,
  lib,
  pkgs,
  vpsadminRev,
  ...
}:
with lib;
let
  cfg = config.vpsadmin.nodectld;
  rndcWrapper = pkgs.writeShellScriptBin "rndc" ''
    exec ${config.services.bind.package}/bin/rndc -k /etc/bind/rndc.key "$@"
  '';
in
{
  imports = [
    ./options.nix
  ];

  config = mkIf cfg.enable {
    vpsadmin.enableOverlay = true;

    vpsadmin.nodectld.settings.mode = "minimal";

    systemd.tmpfiles.rules = [
      "d '/run/nodectl' 0700 root root - -"
      "d '/var/lib/nodectld' 0700 root root - -"
    ];

    systemd.services.vpsadmin-nodectld = {
      description = "vpsAdmin node control daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        rndcWrapper
        config.services.bind.package
        coreutils
        glibc
        iproute2
        ipset
        iptables
        procps
        systemd
      ];
      startLimitIntervalSec = 30;
      startLimitBurst = 4;
      preStart = ''
        ln -sfn /run/current-system/sw/bin/nodectl /run/nodectl/nodectl
      '';
      serviceConfig = {
        Environment = [
          "RUBY_CRASH_REPORT=/dev/null"
          "VPSADMIN_REVISION=${toString vpsadminRev}"
        ];
        Type = "simple";
        # The wrapper runs the transaction watchdog, including on mailers and DNS servers.
        ExecStart = "${pkgs.nodectld}/bin/nodectld";
        # Watchdog recovery can exit the wrapper successfully. Explicit systemd
        # stops still suppress automatic restart.
        Restart = "always";
        RestartSec = 5;
        # Let the wrapper stop its child (TERM, then KILL after 60 seconds),
        # with a final whole-cgroup deadline if the wrapper itself gets stuck.
        KillMode = "mixed";
        TimeoutStopSec = 90;
      };
    };

    environment.systemPackages = with pkgs; [
      nodectl
    ];
  };
}
