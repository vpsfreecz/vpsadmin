{ config, lib, pkgs, utils, ... }:
with lib;
let
  cfg = config.vpsadmin.nodectld;
in {
  options = {
    vpsadmin.nodectld = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable vpsAdmin integration, i.e. include nodectld and nodectl
        '';
      };

      mode = mkOption {
        type = types.enum [ "minimal" "standard" ];
        default = "standard";
        description = ''
          nodectld runtime mode

          Nodes with VPS or storage must use the standard mode. Minimal mode can
          be used for nodes that only execute generic transactions, such as
          sending emails.
        '';
      };

      db = mkOption {
        type = types.submodule {
          options = {
            host = mkOption {
              type = types.str;
              description = "Database hostname";
            };

            user = mkOption {
              type = types.str;
              description = "Database user";
            };

            password = mkOption {
              type = types.str;
              description = "Database password";
            };

            name = mkOption {
              type = types.str;
              description = "Database name";
            };
          };
        };
        default = {
          host = "";
          user = "";
          password = "";
          name = "";
        };
        description = ''
          Database credentials. Don't use this for production deployments, as
          the credentials would be world readable in the Nix store.

          Pass the database credentials through a file in the secrets dir
          configured by <option>system.secretsDir</option>, i.e.
          <literal>''${config.system.secretsDir}/nodectld-config</literal>
        '';
      };

      nodeId = mkOption {
        type = types.int;
        description = "Node ID";
      };

      transactionPublicKeyFile = mkOption {
        type = types.path;
        description = "Path to file with public key used to verify transactions";
        default = "/etc/vpsadmin/transaction.key";
      };

      netInterfaces = mkOption {
        type = types.listOf types.str;
        description = "Network interfaces";
      };

      consoleHost = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Address for console server to listen on";
      };

      mailer = {
        enable = mkEnableOption "Enable vpsAdmin mailer";

        smtpServer = mkOption {
          type = types.str;
          description = "SMTP server hostname";
        };

        smtpPort = mkOption {
          type = types.int;
          description = "SMTP server port";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    environment.etc."vpsadmin/nodectld.yml".source = pkgs.writeText "nodectld-conf" ''
      :mode: ${cfg.mode}
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
  };
}
