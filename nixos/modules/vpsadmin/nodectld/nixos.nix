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

    systemd.tmpfiles.rules = [
      "d '/run/nodectl' 0700 root root - -"
    ];

    systemd.services.vpsadmin-nodectld = {
      description = "vpsAdmin node control daemon";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        coreutils
        glibc
        iproute2
        ipset
        iptables
        procps
      ];
      preStart = ''
        ln -sfn /run/current-system/sw/bin/nodectl /run/nodectl/nodectl
      '';
      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.nodectld}/bin/nodectld --no-wrapper";
      };
    };

    environment.systemPackages = with pkgs; [
      nodectl
    ];
  };
}
