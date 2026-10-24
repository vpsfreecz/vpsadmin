{
  config,
  lib,
  pkgs,
  vpsadminos ? null,
  vpsadminRev,
  ...
}:
with lib;
let
  cfg = config.vpsadmin.nodectld;
  vpsadminosPath =
    if vpsadminos == null then
      null
    else if builtins.isAttrs vpsadminos && vpsadminos ? outPath then
      vpsadminos.outPath
    else
      vpsadminos;
  rubyCrashReportTemplate = config.system.vpsadminos.rubyCrashReportTemplate;
in
{
  imports = [
    ./options.nix
  ];

  config = mkIf cfg.enable {
    nixpkgs.overlays = import ../../../overlays { inherit vpsadminRev vpsadminosPath; };

    environment.etc."nodectl/boot-autostart-version".text = "1\n";

    boot.postBootCommands = ''
      mkdir -m 0700 /run/nodectl
      ln -sfn /run/current-system/sw/bin/nodectl /run/nodectl/nodectl
      # Only an actual boot may enroll a new cohort. Service startup and system
      # activation must preserve missing/corrupt state as unavailable evidence.
      (
        umask 077
        rm -f /run/nodectl/boot-autostart.failed.json
        boot_id=$(cat /proc/sys/kernel/random/boot_id)
        printf '{"schema_version":1,"boot_id":"%s","phase":"enrolling","capture_deadline_boottime_seconds":300,"failure_reason":null,"captured_at_boottime_seconds":null,"obligations":[]}\n' "$boot_id" > /run/nodectl/boot-autostart.json.new
        mv /run/nodectl/boot-autostart.json.new /run/nodectl/boot-autostart.json
      )
    '';

    runit.services.nodectld = {
      path = [
        # Prefer the wrapped osctl-exportfs package. The Ruby dependency also
        # exposes an unwrapped executable without nfs-utils in PATH.
        pkgs.osctl-exportfs
        pkgs.nfs-utils
      ];
      run = ''
        ulimit -c unlimited
        export HOME=${config.users.extraUsers.root.home}
        export LANG=en_US.UTF-8
        export LOCALE_ARCHIVE=/run/current-system/sw/lib/locale/locale-archive
        export VPSADMIN_REVISION=${escapeShellArg (toString vpsadminRev)}
        ${optionalString (!isNull rubyCrashReportTemplate) ''
          export RUBY_CRASH_REPORT=${escapeShellArg rubyCrashReportTemplate}
        ''}
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
      nfs-utils
      nodectl
      openssh
    ];
  };
}
