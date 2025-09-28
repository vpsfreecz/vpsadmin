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

  useLibvirt = cfg.version == "5";

  managedVm = import ./managed-vm.nix { inherit config pkgs lib; };
in
{
  imports = [
    ./options.nix
  ];

  config = mkIf cfg.enable {
    nixpkgs.overlays = import ../../../overlays;

    boot.kernelModules = mkIf useLibvirt [
      "nbd"
    ];

    boot.postBootCommands = ''
      mkdir -p -m 0711 /run/nodectl
      ln -sfn /run/current-system/sw/bin/nodectl /run/nodectl/nodectl
    '';

    system.activationScripts = mkIf useLibvirt {
      nodectl.text = ''
        mkdir -p -m 0711 /run/nodectl
        ln -sfn ${managedVm} /run/nodectl/managed-vm
      '';
    };

    virtualisation.libvirtd.qemu.verbatimConfig = mkIf useLibvirt ''
      # Prevent managed-vm stage2/config drive to be chowned to the qemu user
      # (not working since those are stored in the Nix store)
      dynamic_ownership = 0
    '';

    runit.services.nodectld = {
      path = mkIf useLibvirt (
        with pkgs;
        [
          btrfs-progs
          e2fsprogs
          qemu
          xorriso
        ]
      );
      run = ''
        ulimit -c unlimited
        export HOME=${config.users.extraUsers.root.home}
        export LANG=en_US.UTF-8
        export LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive
        exec 2>&1
        exec ${packages.nodectld}/bin/nodectld --log syslog --log-facility local3
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

    environment.systemPackages =
      with pkgs;
      [
        mbuffer
        openssh
        packages.nodectl
      ]
      ++ optionals useLibvirt [
        console_client
        vmexec
      ];
  };
}
