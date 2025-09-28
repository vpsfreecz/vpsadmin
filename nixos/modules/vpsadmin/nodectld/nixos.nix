{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.vpsadmin.nodectld;

  packages = pkgs."nodectl-v${cfg.version}";
in
{
  imports = [
    ./options.nix
  ];

  config = mkIf cfg.enable {
    vpsadmin.enableOverlay = true;

    # nodectld requires libosctl, which has a native extension that needs
    # patched Ruby to workaround setns/unshare issue on Ruby >=3.3.
    nixpkgs.overlays = mkAfter [
      (import <vpsadminos/os/overlays/ruby.nix>)
    ];

    vpsadmin.nodectld.settings.mode = "minimal";

    systemd.tmpfiles.rules = [
      "d '/run/nodectl' 0700 root root - -"
    ];

    systemd.services.vpsadmin-nodectld = {
      description = "vpsAdmin node control daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
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
        Type = "simple";
        ExecStart = "${packages.nodectld}/bin/nodectld --no-wrapper";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    environment.systemPackages = [
      packages.nodectl
    ];
  };
}
