{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
with lib;
let
  vpsadminCfg = config.vpsadmin;
  cfg = config.vpsadmin.nodectld;

  settingsFormat = pkgs.formats.yaml { };

  configurationYaml = settingsFormat.generate "nodectld.yml" cfg.settings;
in
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

      version = mkOption {
        type = types.enum [
          "4"
          "5"
        ];
        default = "4";
        description = ''
          nodectl major version

          Version 4 is used on nodes with vpsAdminOS/osctld that runs unprivileged
          containers.

          Version 5 is for nodes with libvirt and qemu/kvm.
        '';
      };

      settings = mkOption {
        type = types.submodule {
          freeformType = settingsFormat.type;
        };
        default = { };
        description = ''
          nodectld configuration options
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    vpsadmin.nodectld.settings.rabbitmq = {
      hosts = vpsadminCfg.rabbitmq.hosts;
      vhost = vpsadminCfg.rabbitmq.virtualHost;
    };

    environment.etc."vpsadmin/nodectld.yml".source = configurationYaml;
  };
}
