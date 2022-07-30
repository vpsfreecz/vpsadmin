{ config, lib, pkgs, utils, ... }:
with lib;
{
  options = {
    vpsadmin.nodectld = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable vpsAdmin integration, i.e. include nodectld and nodectl
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
}
