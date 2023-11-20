{ config, pkgs, lib, package, name, databaseConfig, configDirectory, stateDirectory, user, group }:
let
  inherit (lib) concatStringsSep mkOption optionalString types;

  vpsadminCfg = config.vpsadmin;

  databaseYml = pkgs.writeText "database.yml" ''
    production:
      adapter: mysql2
      database: ${databaseConfig.name}
      host: ${databaseConfig.host}
      port: ${toString databaseConfig.port}
      username: ${databaseConfig.user}
      password: #dbpass#
      pool: ${toString databaseConfig.pool}
      ${optionalString (databaseConfig.socket != null) "socket: ${databaseConfig.socket}"}
  '';

  bundle = "${package}/ruby-env/bin/bundle";
in {
  inherit bundle;

  imports = [
    (import ./api-runners.nix name)
  ];

  databaseModule =
    { pool ? 5 }:
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
          default =
            if config.createLocally then
              "/run/mysqld/mysqld.sock"
            else
             null;
          defaultText = "/run/mysqld/mysqld.sock";
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

        createLocally = mkOption {
          type = types.bool;
          default = false;
          description = "Create the database and database user locally.";
        };

        autoSetup = mkOption {
          type = types.bool;
          default = false;
          description = "Automatically run database migrations";
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
    # Cleanup previous state
    rm -f "${stateDirectory}/plugins/"*
    find "${stateDirectory}/config" -type l -exec rm -f {} +

    # Link in configuration
    for v in "${configDirectory}"/* ; do
      ln -sf "$v" "${stateDirectory}/config/$(basename $v)"
    done

    # Link in enabled plugins
    for plugin in ${concatStringsSep " " vpsadminCfg.plugins}; do
      ln -sf "${package}/plugins/$plugin" "${stateDirectory}/plugins/$plugin"
    done

    # Handle database.passwordFile & permissions
    DBPASS=${optionalString (databaseConfig.passwordFile != null) "$(head -n1 ${databaseConfig.passwordFile})"}
    cp -f ${databaseYml} "${stateDirectory}/config/database.yml"
    sed -e "s,#dbpass#,$DBPASS,g" -i "${stateDirectory}/config/database.yml"
    chmod 440 "${stateDirectory}/config/database.yml"

    ${optionalString databaseConfig.autoSetup ''
    # Run database migrations
    ${bundle} exec rake db:migrate
    ${bundle} exec rake vpsadmin:plugins:migrate
    ''}
  '';
}
