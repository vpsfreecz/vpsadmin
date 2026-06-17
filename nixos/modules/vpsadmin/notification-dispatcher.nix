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
        cp -f ${notificationsYml} "${stateDirectory}/config/notifications.yml"
        sed -e "s,#rabbitmq_pass#,$RABBITMQ_PASS,g" -i "${stateDirectory}/config/notifications.yml"
        sed -e "s,#smtp_pass#,$SMTP_PASS,g" -i "${stateDirectory}/config/notifications.yml"
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
            "webhook"
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

      database = mkOption {
        type = types.submodule (apiApp.databaseModule { pool = 5; });
        description = "Database configuration.";
      };
    };
  };

  config = mkIf cfg.enable {
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
