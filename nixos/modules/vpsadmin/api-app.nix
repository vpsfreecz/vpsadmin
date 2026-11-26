{
  config,
  pkgs,
  lib,
  package,
  name,
  databaseConfig,
  configDirectory,
  stateDirectory,
  user,
  group,
}:
let
  inherit (lib)
    concatStringsSep
    mkOption
    optionalString
    types
    ;

  vpsadminCfg = config.vpsadmin;
  logoKeys = {
    logo = "logo_file";
    lightLogo = "light_logo_file";
    darkLogo = "dark_logo_file";
  };
  authentication = vpsadminCfg.deploymentConfig.authentication or { };
  copyLogo =
    name:
    let
      basename = builtins.unsafeDiscardStringContext (
        builtins.baseNameOf vpsadminCfg.authentication.${name}
      );
      extension = lib.toLower (lib.last (lib.splitString "." basename));
      source = builtins.path {
        path = vpsadminCfg.authentication.${name};
        name = "vpsadmin-${name}-${basename}";
      };
    in
    pkgs.runCommand "vpsadmin-${name}-logo.${extension}" { src = source; } ''
      if ! test -f "$src" || ! test -r "$src"; then
        echo "Authentication logo must be a readable regular file" >&2
        exit 1
      fi
      case ${lib.escapeShellArg extension} in
        png|jpg|jpeg|webp|svg) ;;
        *) echo "Unsupported authentication logo file extension" >&2; exit 1 ;;
      esac
      cp -- "$src" "$out"
      chmod 0444 "$out"
    '';
  logoFiles = lib.mapAttrs' (name: key: lib.nameValuePair key (toString (copyLogo name))) (
    lib.filterAttrs (name: _: vpsadminCfg.authentication.${name} != null) logoKeys
  );
  deploymentConfigJson =
    assert lib.assertMsg (builtins.isAttrs authentication)
      "vpsadmin.deploymentConfig.authentication must be an attribute set";
    assert lib.assertMsg
      (!(lib.any (key: builtins.hasAttr key authentication) (builtins.attrValues logoKeys)))
      "Use vpsadmin.authentication logo options instead of reserved deploymentConfig authentication file keys";
    pkgs.writeText "deployment.json" (
      builtins.toJSON (
        vpsadminCfg.deploymentConfig
        // {
          authentication = authentication // logoFiles;
        }
      )
    );

  databaseYml = pkgs.writeText "database.yml" ''
    production:
      adapter: mysql2
      database: ${databaseConfig.name}
      host: ${databaseConfig.host}
      port: ${toString databaseConfig.port}
      username: ${databaseConfig.user}
      password: #dbpass#
      encoding: utf8mb3
      collation: utf8mb3_unicode_ci
      pool: ${toString databaseConfig.pool}
      ${optionalString (databaseConfig.socket != null) "socket: ${databaseConfig.socket}"}
  '';

  bundle = "${package}/ruby-env/bin/bundle";
in
{
  inherit bundle;

  imports = [
    (import ./api-runners.nix name)
  ];

  databaseModule =
    {
      pool ? 5,
    }:
    { config, ... }:
    {
      options = {
        host = mkOption {
          type = types.str;
          default = "localhost";
          description = "Database host address.";
        };

        port = mkOption {
          type = types.int;
          default = 3306;
          defaultText = "3306";
          description = "Database host port.";
        };

        name = mkOption {
          type = types.str;
          default = "vpsadmin";
          description = "Database name.";
        };

        user = mkOption {
          type = types.str;
          default = "vpsadmin-${name}";
          description = "Database user.";
        };

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = "/run/keys/vpsadmin-${name}-dbpassword";
          description = ''
            A file containing the password corresponding to
            <option>database.user</option>.
          '';
        };

        socket = mkOption {
          type = types.nullOr types.path;
          default = null;
          example = "/run/mysqld/mysqld.sock";
          description = "Path to the unix socket file to use for authentication.";
        };

        pool = mkOption {
          type = types.int;
          default = pool;
          description = ''
            Connection pool size
          '';
        };
      };
    };

  tmpfilesRules = [
    "d '${stateDirectory}' 0750 ${user} ${group} - -"
    "d '${stateDirectory}/config' 0750 ${user} ${group} - -"
    "d '${stateDirectory}/plugins' 0750 ${user} ${group} - -"

    "d /run/vpsadmin/${name} - - - - -"
    "L+ /run/vpsadmin/${name}/config - - - - ${stateDirectory}/config"
    "L+ /run/vpsadmin/${name}/plugins - - - - ${stateDirectory}/plugins"
  ];

  setup = ''
    set -euo pipefail
    shopt -s nullglob

    # Cleanup previous state
    rm -f "${stateDirectory}/plugins/"*
    find "${stateDirectory}/config" -type l -exec rm -f {} +

    # Link in configuration
    for v in "${configDirectory}"/* ; do
      ln -sf "$v" "${stateDirectory}/config/$(basename $v)"
    done

    rm -f "${stateDirectory}/config/deployment.json"
    cp -f ${deploymentConfigJson} "${stateDirectory}/config/deployment.json"
    chmod 440 "${stateDirectory}/config/deployment.json"

    # Link in enabled plugins
    for plugin in ${concatStringsSep " " vpsadminCfg.plugins}; do
      ln -sf "${package}/plugins/$plugin" "${stateDirectory}/plugins/$plugin"
    done

    # Handle database.passwordFile & permissions
    DBPASS=${
      optionalString (databaseConfig.passwordFile != null) "$(head -n1 ${databaseConfig.passwordFile})"
    }
    databaseYmlTmp="$(${pkgs.coreutils}/bin/mktemp "${stateDirectory}/config/.database.yml.XXXXXX")"
    trap '${pkgs.coreutils}/bin/rm -f "$databaseYmlTmp"' EXIT
    sed -e "s,#dbpass#,$DBPASS,g" ${databaseYml} >"$databaseYmlTmp"
    chmod 440 "$databaseYmlTmp"
    mv -f "$databaseYmlTmp" "${stateDirectory}/config/database.yml"
    trap - EXIT
  '';
}
