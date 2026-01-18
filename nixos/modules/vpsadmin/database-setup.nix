{
  config,
  lib,
  pkgs,
  ...
}:
let
  vpsadminCfg = config.vpsadmin;

  cfg = vpsadminCfg.databaseSetup;

  apiApp = import ./api-app.nix {
    name = "database";
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

  schemaFile = "${cfg.stateDirectory}/cache/schema.rb";
in
{
  options = {
    vpsadmin.databaseSetup = {
      enable = lib.mkOption {
        type = lib.types.bool;
        readOnly = true;
        default = vpsadminCfg.api.enable || vpsadminCfg.supervisor.enable;
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.vpsadmin-database;
        description = "Which vpsAdmin API package to use.";
        example = "pkgs.vpsadmin-database.override { ruby = pkgs.ruby_3_4; }";
      };

      stateDirectory = lib.mkOption {
        type = lib.types.str;
        default = "${vpsadminCfg.stateDirectory}/database";
        description = "The state directory";
      };

      configDirectory = lib.mkOption {
        type = lib.types.path;
        default = <vpsadmin/api/config>;
        description = "Directory with vpsAdmin configuration files";
      };

      database = lib.mkOption {
        type = lib.types.submodule (apiApp.databaseModule { });
        description = ''
          Database configuration
        '';
      };

      createLocally = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Create the database and database user locally.";
      };

      autoSetup = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Automatically create database and run migrations.";
      };

      seedFiles = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          List of files that are seeded into the database when it is being initialized.

          Relative paths are looked up within the `api/db/seeds` directory and must not
          contain file extension (`.rb` is assumed). Absolute paths must provide file
          extension.
        '';
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "vpsadmin-database";
        description = "User under which the datasbase setup is run";
      };

      group = lib.mkOption {
        type = lib.types.str;
        default = "vpsadmin-database";
        description = "Group under which the database setup is run";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = apiApp.tmpfilesRules ++ [
      "d '${cfg.stateDirectory}/cache' 0750 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.vpsadmin-database-setup = {
      description = "Setup vpsAdmin database, run migrations and seed data";
      wantedBy = [ "multi-user.target" ];
      after = lib.optional cfg.createLocally "mysql.service";
      requires = lib.optional cfg.createLocally "mysql.service";
      path = with pkgs; [
        coreutils
        mariadb
      ];
      environment.RACK_ENV = "production";
      environment.SCHEMA = schemaFile;
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        WorkingDirectory = "${cfg.package}/database";
        RemainAfterExit = "yes";
      };
      script = ''
        ${apiApp.setup}

        ${lib.optionalString (cfg.autoSetup) ''
          dbStateFile="${cfg.stateDirectory}/database-initialized"

          if [ ! -e "${schemaFile}" ] ; then
            cp ${cfg.package}/database/db/schema.rb ${"${cfg.stateDirectory}/cache/schema.rb"}
            chmod 0600 "${cfg.stateDirectory}/cache/schema.rb"
          fi

          if [ -e "$dbStateFile" ]; then
            dbInitialized=yes
            echo "Database is already initialized"
          else
            dbInitialized=no
            echo "Loading database schema"
            ${apiApp.bundle} exec rake db:schema:load
            date > "$dbStateFile"
          fi

          echo "Running database migrations"
          ${apiApp.bundle} exec rake db:migrate

          echo "Running plugin migrations"
          ${apiApp.bundle} exec rake vpsadmin:plugins:migrate

          if [ "$dbInitialized" == "no" ]; then
            ${lib.concatMapStringsSep "\n" (file: ''
              echo "Seeding file ${file}"
              ${apiApp.bundle} exec rake db:seed:file SEED_FILE=${file}
            '') cfg.seedFiles}
          fi
        ''}
      '';
    };

    users.users = lib.optionalAttrs (cfg.user == "vpsadmin-database") {
      ${cfg.user} = {
        group = cfg.group;
        home = cfg.stateDirectory;
        isSystemUser = true;
      };
    };

    users.groups = lib.optionalAttrs (cfg.group == "vpsadmin-database") {
      ${cfg.group} = { };
    };
  };
}
