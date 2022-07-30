{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.vpsadmin.nodectld;
in {
  imports = [
    ./options.nix
  ];

  config = mkMerge [
    (mkIf cfg.enable {
      nixpkgs.overlays = import ../../../overlays;

      boot.postBootCommands = ''
        mkdir -m 0700 /run/nodectl
        ln -sfn /run/current-system/sw/bin/nodectl /run/nodectl/nodectl
      '';

      environment.etc."vpsadmin/nodectld.yml".source = pkgs.writeText "nodectld-conf" ''
        ${optionalString (cfg.db.host != "") ''
        :db:
          :host: ${cfg.db.host}
          :user: ${cfg.db.user}
          :pass: ${cfg.db.password}
          :name: ${cfg.db.name}
        ''}
        :vpsadmin:
          :node_id: ${toString cfg.nodeId}
          :net_interfaces: [${concatStringsSep ", " cfg.netInterfaces}]
          :transaction_public_key: ${cfg.transactionPublicKeyFile}
        ${optionalString (cfg.consoleHost != null) ''
        :console:
          :host: ${cfg.consoleHost}
        ''}
        ${optionalString cfg.mailer.enable ''
        :mailer:
          :smtp_server: ${cfg.mailer.smtpServer}
          :smtp_port: ${toString cfg.mailer.smtpPort}
        ''}
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

      environment.systemPackages = with pkgs; [
        mbuffer
        nodectl
      ];
    })
  ];
}
