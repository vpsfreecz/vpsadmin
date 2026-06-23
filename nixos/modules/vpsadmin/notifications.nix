{
  config,
  lib,
  ...
}:
with lib;
let
  telegramCfg = config.vpsadmin.notifications.telegram;
  smsCfg = config.vpsadmin.notifications.sms;
  positiveInt = types.addCheck types.int (value: value >= 1);
  nonNegativeInt = types.addCheck types.int (value: value >= 0);
in
{
  options.vpsadmin.notifications = {
    telegram = {
      enable = mkEnableOption "Enable Telegram notifications in vpsAdmin";

      botTokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/keys/vpsadmin-telegram-bot-token";
        description = ''
          File containing the Telegram bot token used to pair chats and send
          Telegram notification messages. Keep unset when Telegram delivery is
          not enabled.
        '';
      };

      botUsername = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "vpsadmin_bot";
        description = ''
          Public Telegram bot username without the leading @. Used by vpsAdmin
          to show pairing links such as https://t.me/<bot_username>.
        '';
      };

      apiBaseUrl = mkOption {
        type = types.str;
        default = "https://api.telegram.org";
        description = ''
          Telegram Bot API base URL. Override this when using a local Bot API
          server or a test double in development.
        '';
      };

      receiveMode = mkOption {
        type = types.enum [
          "polling"
          "webhook"
        ];
        default = "polling";
        description = ''
          How vpsAdmin receives Telegram updates for chat pairing.
        '';
      };

      polling = {
        timeout = mkOption {
          type = nonNegativeInt;
          default = 50;
          description = ''
            Long-poll timeout in seconds. Values above Telegram's limit are
            clamped by vpsAdmin.
          '';
        };

        limit = mkOption {
          type = positiveInt;
          default = 100;
          description = ''
            Maximum number of Telegram updates fetched by one long-poll request.
            Values above Telegram's limit are clamped by vpsAdmin.
          '';
        };

        retryDelay = mkOption {
          type = positiveInt;
          default = 5;
          description = ''
            Delay in seconds before retrying after a polling error.
          '';
        };

        deleteWebhook = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Ask Telegram to delete any configured webhook before entering polling
            mode.
          '';
        };
      };

      webhook = {
        listenAddress = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Address on which the Telegram receiver listens.";
        };

        port = mkOption {
          type = types.int;
          default = 9293;
          description = "Port on which the Telegram receiver listens.";
        };

        path = mkOption {
          type = types.str;
          default = "/_telegram/webhook";
          description = "Public path receiving Telegram webhook updates.";
        };

        publicUrl = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "https://api.example.org/_telegram/webhook";
          description = ''
            Public URL registered with Telegram when webhook mode is enabled and
            automatic registration is on.
          '';
        };

        secretTokenFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = "/run/keys/vpsadmin-telegram-webhook-secret";
          description = ''
            File containing the secret token Telegram sends in the
            X-Telegram-Bot-Api-Secret-Token request header.
          '';
        };

        autoRegister = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Register the webhook with Telegram when the receiver service starts.
          '';
        };
      };
    };

    sms = {
      enable = mkEnableOption "Enable SMS notifications in vpsAdmin";

      callbackTokenFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/run/keys/vpsadmin-sms-callback-token";
        description = ''
          Optional legacy bearer token accepted for SMS gateway callbacks that
          were queued before per-message HMAC callback secrets were available.
        '';
      };

      callbackUrl = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "https://api.example.org/internal/notifications/sms/callback";
        description = ''
          Public or internal URL used by SMS gateways to report final delivery
          state. When unset, vpsAdmin derives it from core.api_url.
        '';
      };

      verificationText = mkOption {
        type = types.str;
        default = "Your vpsAdmin verification code is %{code}";
        description = "SMS text used for phone number verification.";
      };

      openTimeout = mkOption {
        type = positiveInt;
        default = 5;
        description = "SMS gateway connection timeout in seconds.";
      };

      readTimeout = mkOption {
        type = positiveInt;
        default = 15;
        description = "SMS gateway read timeout in seconds.";
      };

      gateways = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              name = mkOption {
                type = types.str;
                description = "Stable SMS gateway name, e.g. brq or prg.";
              };

              url = mkOption {
                type = types.str;
                example = "http://apu.int.brq:9876/v1/sms";
                description = "SMS gateway HTTP API endpoint.";
              };

              tokenFile = mkOption {
                type = types.path;
                description = "File containing the gateway bearer token.";
              };
            };
          }
        );
        default = [ ];
        description = ''
          Ordered SMS gateways. vpsAdmin tries them in order, so production can
          prefer BRQ first and PRG second while Alertmanager uses the inverse.
        '';
      };
    };
  };

  config.assertions = [
    {
      assertion = !telegramCfg.enable || telegramCfg.botTokenFile != null;
      message = "vpsadmin.notifications.telegram.botTokenFile must be set when Telegram is enabled";
    }
    {
      assertion =
        !telegramCfg.enable
        || telegramCfg.receiveMode != "webhook"
        || !telegramCfg.webhook.autoRegister
        || telegramCfg.webhook.publicUrl != null;
      message = "vpsadmin.notifications.telegram.webhook.publicUrl must be set when webhook auto-registration is enabled";
    }
    {
      assertion =
        !telegramCfg.enable
        || telegramCfg.receiveMode != "webhook"
        || !telegramCfg.webhook.autoRegister
        || telegramCfg.webhook.secretTokenFile != null;
      message = "vpsadmin.notifications.telegram.webhook.secretTokenFile must be set when webhook auto-registration is enabled";
    }
    {
      assertion = !smsCfg.enable || smsCfg.gateways != [ ];
      message = "vpsadmin.notifications.sms.gateways must not be empty when SMS is enabled";
    }
  ];
}
