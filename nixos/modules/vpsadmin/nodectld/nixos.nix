{
  config,
  lib,
  pkgs,
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
      ];
      startLimitIntervalSec = 30;
      startLimitBurst = 4;
      preStart = ''
        ln -sfn /run/current-system/sw/bin/nodectl /run/nodectl/nodectl
      '';
      serviceConfig = {
        Environment = "RUBY_CRASH_REPORT=/dev/null";
        Type = "simple";
        ExecStart = "${pkgs.nodectld}/bin/nodectld --no-wrapper";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    environment.systemPackages = with pkgs; [
      nodectl
    ];
  };
}
