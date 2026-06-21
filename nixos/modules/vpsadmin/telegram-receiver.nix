{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.telegramReceiver;
  telegramCfg = config.vpsadmin.notifications.telegram;
  vpsadminRoot = toString (./../../..);

  apiApp = import ./api-app.nix {
    name = "telegramReceiver";
    inherit config pkgs lib;
    inherit (cfg)
      package
      user
      group
      configDirectory
      stateDirectory
      ;
    databaseConfig = cfg.database;
  };

  notificationsYml = pkgs.writeText "notifications.yml" (
    builtins.toJSON {
      telegram = {
        enabled = telegramCfg.enable;
        configured = telegramCfg.enable && telegramCfg.botTokenFile != null;
        bot_token = "#telegram_bot_token#";
        api_base_url = telegramCfg.apiBaseUrl;
        receive_mode = telegramCfg.receiveMode;
        polling = {
          timeout = telegramCfg.polling.timeout;
          limit = telegramCfg.polling.limit;
          retry_delay = telegramCfg.polling.retryDelay;
          delete_webhook = telegramCfg.polling.deleteWebhook;
        };
        webhook = {
          listen_address = telegramCfg.webhook.listenAddress;
          port = telegramCfg.webhook.port;
          path = telegramCfg.webhook.path;
          public_url = telegramCfg.webhook.publicUrl;
          secret_token = "#telegram_webhook_secret#";
          auto_register = telegramCfg.webhook.autoRegister;
        };
      };
    }
  );
in
{
  imports = apiApp.imports;

  options.vpsadmin.telegramReceiver = {
    enable = mkEnableOption "Enable vpsAdmin Telegram update receiver";

    package = mkOption {
      type = types.package;
      default = pkgs.vpsadmin-telegram-receiver;
      description = "Which vpsAdmin Telegram receiver package to use.";
      example = "pkgs.vpsadmin-telegram-receiver.override { ruby = pkgs.ruby_3_4; }";
    };

    user = mkOption {
      type = types.str;
      default = "vpsadmin-telegram-receiver";
      description = "User under which the Telegram receiver runs";
    };

    group = mkOption {
      type = types.str;
      default = "vpsadmin-telegram-receiver";
      description = "Group under which the Telegram receiver runs";
    };

    stateDirectory = mkOption {
      type = types.str;
      default = "${vpsadminCfg.stateDirectory}/telegram-receiver";
      description = "The state directory, logs and plugins are stored here.";
    };

    configDirectory = mkOption {
      type = types.path;
      default = "${vpsadminRoot}/api/config";
      description = "Directory with vpsAdmin configuration files";
    };

    allowedIPv4Ranges = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        List of IPv4 ranges allowed to access the webhook listener.
      '';
    };

    allowedIPv6Ranges = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = ''
        List of IPv6 ranges allowed to access the webhook listener.
      '';
    };

    database = mkOption {
      type = types.submodule (apiApp.databaseModule { pool = 5; });
      description = ''
        Database configuration.
      '';
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = telegramCfg.enable;
        message = "vpsadmin.telegramReceiver.enable requires vpsadmin.notifications.telegram.enable";
      }
    ];

    vpsadmin = {
      enableOverlay = true;
      enableStateDirectory = true;
    };

    networking.firewall.extraCommands = optionalString (telegramCfg.receiveMode == "webhook") (
      concatStringsSep "\n" (
        flatten (
          (map (ip: ''
            iptables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString telegramCfg.webhook.port} -j nixos-fw-accept
          '') cfg.allowedIPv4Ranges)
          ++ (map (ip: ''
            ip6tables -A nixos-fw -p tcp -m tcp -s ${ip} --dport ${toString telegramCfg.webhook.port} -j nixos-fw-accept
          '') cfg.allowedIPv6Ranges)
        )
      )
    );

    systemd.tmpfiles.rules = apiApp.tmpfilesRules ++ [
      "d '${cfg.stateDirectory}/cache' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/log' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${cfg.stateDirectory}/pids' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.vpsadmin-telegram-receiver = {
      description = "vpsAdmin Telegram update receiver";
      after = [
        "network.target"
        "vpsadmin-database-setup.service"
      ];
      requires = [ "vpsadmin-database-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      path = with pkgs; [
        mariadb
      ];
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      environment = {
        RACK_ENV = "production";
        SCHEMA = "${cfg.stateDirectory}/cache/schema.rb";
        VPSADMIN_NOTIFICATIONS_CONFIG = "${cfg.stateDirectory}/config/notifications.yml";
        VPSADMIN_ROOT = "${cfg.package}/telegramReceiver";
      };
      preStart = ''
        ${apiApp.setup}

        TELEGRAM_BOT_TOKEN=${
          optionalString (telegramCfg.botTokenFile != null) "$(head -n1 ${telegramCfg.botTokenFile})"
        }
        TELEGRAM_WEBHOOK_SECRET=${
          optionalString (
            telegramCfg.webhook.secretTokenFile != null
          ) "$(head -n1 ${telegramCfg.webhook.secretTokenFile})"
        }
        cp -f ${notificationsYml} "${cfg.stateDirectory}/config/notifications.yml"
        sed -e "s,#telegram_bot_token#,$TELEGRAM_BOT_TOKEN,g" -i "${cfg.stateDirectory}/config/notifications.yml"
        sed -e "s,#telegram_webhook_secret#,$TELEGRAM_WEBHOOK_SECRET,g" -i "${cfg.stateDirectory}/config/notifications.yml"
        chmod 440 "${cfg.stateDirectory}/config/notifications.yml"
      '';
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/telegramReceiver";
        ExecStart = "${apiApp.bundle} exec bin/vpsadmin-telegram-receiver";
        Restart = "on-failure";
        RestartSec = 30;
      };
    };

    users.users = optionalAttrs (cfg.user == "vpsadmin-telegram-receiver") {
      ${cfg.user} = {
        group = cfg.group;
        home = cfg.stateDirectory;
        isSystemUser = true;
      };
    };

    users.groups = optionalAttrs (cfg.group == "vpsadmin-telegram-receiver") {
      ${cfg.group} = { };
    };
  };
}
