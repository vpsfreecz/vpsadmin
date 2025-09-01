{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.vpsadmin.nodectld;

  managedVm = import ./managed-vm.nix { inherit config pkgs lib; };
in
{
  imports = [
    ./options.nix
  ];

  config = mkIf cfg.enable {
    nixpkgs.overlays = import ../../../overlays;

    boot.postBootCommands = ''
      mkdir -m 0700 /run/nodectl
      ln -sfn /run/current-system/sw/bin/nodectl /run/nodectl/nodectl
    '';

    system.activationScripts.nodectl.text = ''
      ln -sfn ${managedVm} /run/nodectl/managed-vm
    '';

    runit.services.nodectld = {
      run = ''
        ulimit -c unlimited
        export HOME=${config.users.extraUsers.root.home}
        export LANG=en_US.UTF-8
        export LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive
        exec 2>&1
        exec ${pkgs.nodectld}/bin/nodectld --log syslog --log-facility local3
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
