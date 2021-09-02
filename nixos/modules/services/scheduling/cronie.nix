{ config, lib, pkgs, ... }:
with lib;
{
  options = {
    services.cron = {
      permitAnyCrontab = mkOption {
        type = types.bool;
        default = false;
        description = "Allow cron to accept any user crontables.";
      };
    };
  };

  config = mkIf config.services.cron.enable {
    systemd.tmpfiles.rules = [
      "d /etc/cron.d - - - - -"
      "d /var/spool/cron 0700 - - - -"
    ];

    systemd.services.cron = {
      preStart = mkForce ''
        # By default, allow all users to create a crontab.  This
        # is denoted by the existence of an empty cron.deny file.
        if ! test -e /etc/cron.allow -o -e /etc/cron.deny; then
          touch /etc/cron.deny
        fi
      '';

      serviceConfig.ExecStart = mkForce (toString ([
        "${pkgs.cron}/bin/crond"
        "-n"
      ] ++ optional config.services.cron.permitAnyCrontab [ "-p" ]));
    };
  };
}
