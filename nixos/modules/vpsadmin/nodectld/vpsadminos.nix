{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.vpsadmin.nodectld;

  kernelSecurity = "/run/vpsadmin/sys-kernel-security";

  moduleAppArmor = "/run/vpsadmin/sys-module-apparmor";
in {
  imports = [
    ./options.nix
  ];

  config = mkIf cfg.enable {
    nixpkgs.overlays = import ../../../overlays;

    boot.postBootCommands = ''
      mkdir -m 0700 /run/nodectl
      ln -sfn /run/current-system/sw/bin/nodectl /run/nodectl/nodectl

      # Prepare a directory that is then used to hide AppArmor inside a VPS
      # by over-mounting directories in /sys
      mkdir -p ${kernelSecurity}
      mount -t tmpfs -o mode=755,size=65536 tmpfs ${kernelSecurity}
      echo "[none] integrity confidentiality" > ${kernelSecurity}/lockdown
      echo "capability,lockdown,yama" > ${kernelSecurity}/lsm
      chmod 0444 ${kernelSecurity}/lsm
      mkdir ${kernelSecurity}/integrity
      mount -o remount,ro ${kernelSecurity}

      mkdir -p ${moduleAppArmor}
      mount -t tmpfs -o ro,mode=755,size=65536 tmpfs ${moduleAppArmor}
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

    runit.halt.reasonTemplates."10-vpsadmin-outages".source = pkgs.writeScript "vpsadmin-outages.sh" ''
      #!${pkgs.bash}/bin/bash

      if [ $# != 0 ] ; then
        echo "Usage: $0"
        exit 1
      fi

      cat >> "$HALT_REASON_FILE" <<EOF
      #
      ### vpsAdmin Outage Reports for $(hostname)
      #
      EOF

      nodectl halt-reason >> "$HALT_REASON_FILE"
    '';

    environment.systemPackages = with pkgs; [
      mbuffer
      nodectl
      openssh
    ];
  };
}
