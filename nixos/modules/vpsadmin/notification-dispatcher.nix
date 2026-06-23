{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.notificationDispatcher;
  telegramCfg = config.vpsadmin.notifications.telegram;
  smsCfg = config.vpsadmin.notifications.sms;
  vpsadminRoot = toString (./../../..);

  apiAppFor =
    stateDirectory:
    import ./api-app.nix {
      name = "notificationDispatcher";
      inherit config pkgs lib;
      inherit (cfg)
        package
        user
        group
        configDirectory
        ;
      inherit stateDirectory;
      databaseConfig = cfg.database;
      runLinks = false;
    };

  apiApp = apiAppFor cfg.stateDirectory;

  actionStateDirectory = action: "${cfg.stateDirectory}/${action}";

  actionApiApp = action: apiAppFor (actionStateDirectory action);

  positiveInt = types.addCheck types.int (value: value >= 1);
  nonNegativeInt = types.addCheck types.int (value: value >= 0);
  telegramBotTokenCredential = "telegram-bot-token";
  smsCallbackTokenCredential = "sms-callback-token";
  smsGatewayTokenCredential = gateway: "sms-gateway-${gateway.name}-token";
  readCredential = name: ''$(head -n1 "$CREDENTIALS_DIRECTORY/${name}")'';

  smsCredentials =
    optional (smsCfg.enable && smsCfg.callbackTokenFile != null) (
      "${smsCallbackTokenCredential}:${smsCfg.callbackTokenFile}"
    )
    ++ optionals smsCfg.enable (
      map (gateway: "${smsGatewayTokenCredential gateway}:${gateway.tokenFile}") smsCfg.gateways
    );

  smsGatewayConfig = imap0 (index: gateway: {
    inherit (gateway) name url;
    token = "#sms_gateway_${toString index}_token#";
  }) smsCfg.gateways;

  smsTokenSubstitutions =
    stateDirectory:
    concatStringsSep "\n" (
      (optional (smsCfg.enable && smsCfg.callbackTokenFile != null) ''
        sed -e "s,#sms_callback_token#,${readCredential smsCallbackTokenCredential},g" -i "${stateDirectory}/config/notifications.yml"
      '')
      ++ imap0 (index: gateway: ''
        sed -e "s,#sms_gateway_${toString index}_token#,${readCredential (smsGatewayTokenCredential gateway)},g" -i "${stateDirectory}/config/notifications.yml"
      '') smsCfg.gateways
    );

  actionTmpfilesRules =
    action:
    let
      app = actionApiApp action;
      stateDirectory = actionStateDirectory action;
      runtimeRoot = "${stateDirectory}/app";
    in
    app.tmpfilesRules
    ++ [
      "d '${runtimeRoot}' 0750 ${cfg.user} ${cfg.group} - -"
      "d '${stateDirectory}/cache' 0750 ${cfg.user} ${cfg.group} - -"
    ];

  smtpConfig = {
    address = cfg.smtp.address;
    port = cfg.smtp.port;
    open_timeout = cfg.smtp.openTimeout;
    read_timeout = cfg.smtp.readTimeout;
    username = cfg.smtp.username;
    password = "#smtp_pass#";
    authentication = cfg.smtp.authentication;
    enable_starttls_auto = cfg.smtp.enableStarttlsAuto;
  };

  notificationsYml = pkgs.writeText "notifications.yml" (
    builtins.toJSON {
      rabbitmq = {
        hosts = vpsadminCfg.rabbitmq.hosts;
        vhost = vpsadminCfg.rabbitmq.virtualHost;
        username = cfg.rabbitmq.username;
        password = "#rabbitmq_pass#";
      };
      smtp = smtpConfig;
      email = {
        concurrency = cfg.email.concurrency;
        worker_delay = cfg.email.workerDelay;
        domain_min_delivery_interval = cfg.email.domainMinDeliveryInterval;
      };
      telegram = {
        enabled = telegramCfg.enable;
        configured = telegramCfg.enable && telegramCfg.botTokenFile != null;
        concurrency = cfg.telegram.concurrency;
        bot_token = "#telegram_bot_token#";
        bot_username = telegramCfg.botUsername;
        api_base_url = telegramCfg.apiBaseUrl;
      };
      webhook = {
        concurrency = cfg.webhook.concurrency;
        allowed_untracked_private_ranges = cfg.webhook.allowedUntrackedPrivateRanges;
      };
      sms = {
        enabled = smsCfg.enable;
        configured = smsCfg.enable && smsCfg.gateways != [ ];
        concurrency = cfg.sms.concurrency;
        callback_url = smsCfg.callbackUrl;
        verification_text = smsCfg.verificationText;
        open_timeout = smsCfg.openTimeout;
        read_timeout = smsCfg.readTimeout;
        gateways = smsGatewayConfig;
      }
      // optionalAttrs (smsCfg.callbackTokenFile != null) {
        callback_token = "#sms_callback_token#";
      };
      poll_interval = cfg.pollInterval;
    }
  );

  dispatcherService =
    action:
    let
      app = actionApiApp action;
      stateDirectory = actionStateDirectory action;
      runtimeRoot = "${stateDirectory}/app";
    in
    nameValuePair "vpsadmin-notification-dispatcher-${action}" {
      description = "vpsAdmin notification dispatcher for ${action}";
      after = [
        "network.target"
        "vpsadmin-database-setup.service"
      ];
      requires = [ "vpsadmin-database-setup.service" ];
      wantedBy = [ "multi-user.target" ];
      environment.RACK_ENV = "production";
      environment.SCHEMA = "${stateDirectory}/cache/schema.rb";
      environment.VPSADMIN_NOTIFICATIONS_CONFIG = "${stateDirectory}/config/notifications.yml";
      environment.VPSADMIN_ROOT = runtimeRoot;
      path = with pkgs; [
        mariadb
      ];
      startLimitIntervalSec = 180;
      startLimitBurst = 5;
      preStart = ''
        ${app.setup}

        RABBITMQ_PASS=${
          optionalString (cfg.rabbitmq.passwordFile != null) "$(head -n1 ${cfg.rabbitmq.passwordFile})"
        }
        SMTP_PASS=${optionalString (cfg.smtp.passwordFile != null) "$(head -n1 ${cfg.smtp.passwordFile})"}
        TELEGRAM_BOT_TOKEN=${
          optionalString (telegramCfg.botTokenFile != null) (readCredential telegramBotTokenCredential)
        }
        cp -f ${notificationsYml} "${stateDirectory}/config/notifications.yml"
        sed -e "s,#rabbitmq_pass#,$RABBITMQ_PASS,g" -i "${stateDirectory}/config/notifications.yml"
        sed -e "s,#smtp_pass#,$SMTP_PASS,g" -i "${stateDirectory}/config/notifications.yml"
        sed -e "s,#telegram_bot_token#,$TELEGRAM_BOT_TOKEN,g" -i "${stateDirectory}/config/notifications.yml"
        ${optionalString smsCfg.enable (smsTokenSubstitutions stateDirectory)}
        chmod 440 "${stateDirectory}/config/notifications.yml"

        rm -rf "${runtimeRoot}"
        install -d -o ${cfg.user} -g ${cfg.group} -m 0750 "${runtimeRoot}"

        for entry in "${cfg.package}/notificationDispatcher/"*; do
          name="$(basename "$entry")"
          case "$name" in
            config|plugins)
              continue
              ;;
          esac

          ln -s "$entry" "${runtimeRoot}/$name"
        done

        ln -s "${stateDirectory}/config" "${runtimeRoot}/config"
        ln -s "${stateDirectory}/plugins" "${runtimeRoot}/plugins"
      '';
      serviceConfig = {
        Type = "simple";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = runtimeRoot;
        ExecStart = "${app.bundle} exec bin/vpsadmin-notification-dispatcher ${action}";
        Restart = "on-failure";
        RestartSec = 30;
        LoadCredential =
          (optional (
            telegramCfg.botTokenFile != null
          ) "${telegramBotTokenCredential}:${telegramCfg.botTokenFile}")
          ++ smsCredentials;
      };
    };
in
{
  imports = apiApp.imports;

  options = {
    vpsadmin.notificationDispatcher = {
      enable = mkEnableOption "Enable vpsAdmin notification dispatchers";

      package = mkOption {
        type = types.package;
        default = pkgs.vpsadmin-notification-dispatcher;
        description = "Which vpsAdmin notification dispatcher package to use.";
        example = "pkgs.vpsadmin-notification-dispatcher.override { ruby = pkgs.ruby_3_4; }";
      };

      user = mkOption {
        type = types.str;
        default = "vpsadmin-notifications";
        description = "User under which notification dispatchers run";
      };

      group = mkOption {
        type = types.str;
        default = "vpsadmin-notifications";
        description = "Group under which notification dispatchers run";
      };

      actions = mkOption {
        type = types.listOf (
          types.enum [
            "email"
            "telegram"
            "webhook"
            "sms"
          ]
        );
        default = [
          "email"
          "webhook"
        ];
        description = "Notification actions to dispatch.";
      };

      pollInterval = mkOption {
        type = types.int;
        default = 5;
        description = ''
          Database reconciliation interval in seconds.
          RabbitMQ still wakes dispatchers immediately when messages arrive.
        '';
      };

      stateDirectory = mkOption {
        type = types.str;
        default = "${vpsadminCfg.stateDirectory}/notification-dispatcher";
        description = "The state directory, logs and plugins are stored here.";
      };

      configDirectory = mkOption {
        type = types.path;
        default = "${vpsadminRoot}/api/config";
        description = "Directory with vpsAdmin configuration files";
      };

      rabbitmq = {
        username = mkOption {
          type = types.str;
          description = "RabbitMQ username";
        };

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to a file containing the RabbitMQ password.";
        };
      };

      email = {
        concurrency = mkOption {
          type = positiveInt;
          default = 2;
          description = ''
            Number of concurrent e-mail delivery workers. Per-domain and
            per-worker throttles are shared by workers in one dispatcher
            process.
          '';
        };

        workerDelay = mkOption {
          type = nonNegativeInt;
          default = 1;
          description = ''
            Minimum delay in seconds between e-mail delivery starts made by the
            same worker. Set to 0 to disable this per-worker throttle.
          '';
        };

        domainMinDeliveryInterval = mkOption {
          type = nonNegativeInt;
          default = 1;
          description = ''
            Minimum delay in seconds between e-mail delivery starts to the same
            recipient domain within one dispatcher process. Domains are taken
            from To, Cc, and Bcc recipients. Set to 0 to disable this throttle.
          '';
        };
      };

      telegram = {
        concurrency = mkOption {
          type = positiveInt;
          default = 2;
          description = ''
            Number of concurrent Telegram delivery workers.
          '';
        };

      };

      sms = {
        concurrency = mkOption {
          type = positiveInt;
          default = 1;
          description = ''
            Number of concurrent SMS delivery workers.
          '';
        };
      };

      smtp = {
        address = mkOption {
          type = types.str;
          default = "localhost";
          description = "SMTP server address.";
        };

        port = mkOption {
          type = types.int;
          default = 25;
          description = "SMTP server port.";
        };

        username = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "SMTP username.";
        };

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "Path to a file containing the SMTP password.";
        };

        authentication = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "SMTP authentication mechanism.";
        };

        enableStarttlsAuto = mkOption {
          type = types.nullOr types.bool;
          default = null;
          description = "Whether to enable STARTTLS automatically.";
        };

        openTimeout = mkOption {
          type = types.int;
          default = 30;
          description = "SMTP connection timeout in seconds.";
        };

        readTimeout = mkOption {
          type = types.int;
          default = 60;
          description = "SMTP read timeout in seconds.";
        };
      };

      webhook = {
        concurrency = mkOption {
          type = positiveInt;
          default = 4;
          description = ''
            Number of concurrent webhook delivery workers.
          '';
        };

        allowedUntrackedPrivateRanges = mkOption {
          type = types.listOf types.str;
          default = [ ];
          example = [
            "127.0.0.0/8"
          ];
          description = ''
            Private, loopback, link-local, or otherwise reserved destination
            ranges that webhook delivery is allowed to call when the address is
            not managed by vpsAdmin. vpsAdmin-managed addresses are allowed only
            when they currently belong to the event user.
          '';
        };
      };

      database = mkOption {
        type = types.submodule (apiApp.databaseModule { pool = 5; });
        description = "Database configuration.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = !(elem "telegram" cfg.actions) || telegramCfg.enable;
        message = "telegram notification dispatching requires vpsadmin.notifications.telegram.enable";
      }
      {
        assertion = !(elem "sms" cfg.actions) || smsCfg.enable;
        message = "sms notification dispatching requires vpsadmin.notifications.sms.enable";
      }
    ];

    vpsadmin = {
      enableOverlay = true;
      enableStateDirectory = true;
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDirectory}' 0750 ${cfg.user} ${cfg.group} - -"
    ]
    ++ concatMap actionTmpfilesRules cfg.actions;

    systemd.services = listToAttrs (map dispatcherService cfg.actions);

    users.users = optionalAttrs (cfg.user == "vpsadmin-notifications") {
      ${cfg.user} = {
        group = cfg.group;
        home = cfg.stateDirectory;
        isSystemUser = true;
      };
    };

    users.groups = optionalAttrs (cfg.group == "vpsadmin-notifications") {
      ${cfg.group} = { };
    };
  };
}
