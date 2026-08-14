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

    vpsadmin.nodectld.settings.dns_server = {
      transfer_probe_systemd_run_command = "${pkgs.systemd}/bin/systemd-run";
      transfer_probe_systemctl_command = "${pkgs.systemd}/bin/systemctl";
      transfer_probe_worker_command = "${pkgs.nodectld}/bin/vpsadmin-dns-transfer-probe";
      transfer_probe_dig_command = "${getOutput "dnsutils" config.services.bind.package}/bin/dig";
      transfer_probe_checkconf_command = "${config.services.bind.package}/bin/named-checkconf";
    };

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
        dnsutils
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
