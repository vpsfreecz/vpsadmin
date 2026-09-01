{
  description = "vpsAdmin (NixOS/vpsAdminOS modules and packages)";

  inputs = {
    vpsadminos.url = "github:vpsfreecz/vpsadminos/staging";
    nixpkgs.follows = "vpsadminos/nixpkgs";
  };

  outputs =
    {
      self,
      vpsadminos,
      nixpkgs,
    }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      flakeDirty = !(self ? rev) && self ? dirtyRev;
      flakeRevision =
        if self ? rev then
          self.rev
        else if self ? dirtyRev then
          nixpkgs.lib.removeSuffix "-dirty" self.dirtyRev
        else
          null;
      vpsadminosVersion = "${
        nixpkgs.lib.removeSuffix "\n" (builtins.readFile (vpsadminos.outPath + "/.version"))
      }.0";
      overlayList = import ./nixos/overlays/default.nix {
        vpsadminRev = flakeRevision;
        vpsadminosPath = vpsadminos.outPath;
      };
      vpsadminosRubyOverlay = import (vpsadminos.outPath + "/os/overlays/ruby.nix");

      composeExtensions =
        f: g: final: prev:
        let
          fApplied = f final prev;
          gApplied = g final (prev // fApplied);
        in
        fApplied // gApplied;

      composeManyExtensions = overlays: builtins.foldl' composeExtensions (final: prev: { }) overlays;

      composedOverlay = composeManyExtensions ([ vpsadminosRubyOverlay ] ++ overlayList);

      notificationTemplateToolsFor =
        system: nixpkgs.legacyPackages.${system}.callPackage ./packages/notification-templates { };

      notificationTemplatesLib = {
        mkPackage =
          {
            system,
            src,
            pname ? "vpsadmin-notification-templates",
          }:
          (notificationTemplateToolsFor system).mkPackage { inherit pname src; };

        mkFlake =
          {
            src,
            pname ? "vpsadmin-notification-templates",
          }:
          let
            templatePackages = forAllSystems (
              system:
              (notificationTemplateToolsFor system).mkPackage {
                inherit pname src;
              }
            );
          in
          {
            packages = forAllSystems (system: {
              default = templatePackages.${system};
            });

            checks = forAllSystems (system: {
              default = templatePackages.${system};
            });

            apps = forAllSystems (
              system:
              let
                pkgs = nixpkgs.legacyPackages.${system};
                check = pkgs.writeShellApplication {
                  name = "check-notification-templates";
                  text = ''
                    exec ${(notificationTemplateToolsFor system).checker}/bin/notification-template-check ${nixpkgs.lib.escapeShellArg (toString src)}
                  '';
                };
              in
              {
                check = {
                  type = "app";
                  program = "${check}/bin/check-notification-templates";
                  meta.description = "Check vpsAdmin notification templates";
                };
              }
            );

            devShells = forAllSystems (
              system:
              let
                pkgs = nixpkgs.legacyPackages.${system};
              in
              {
                default = pkgs.mkShell {
                  packages = [ (notificationTemplateToolsFor system).checker ];
                };
              }
            );
          };
      };
    in
    {
      lib.notificationTemplates = notificationTemplatesLib;

      nixosModules = {
        nixos-modules =
          { ... }:
          {
            _module.args = {
              inherit vpsadminos;
              vpsadminRev = flakeRevision;
              vpsadminRevisionDirty = flakeDirty;
            };
            imports = [ ./nixos/modules/nixos-modules.nix ];
          };
        vpsadminos-modules =
          { ... }:
          {
            _module.args = {
              inherit vpsadminos;
              vpsadminRev = flakeRevision;
              vpsadminRevisionDirty = flakeDirty;
            };
            imports = [ ./nixos/modules/vpsadminos-modules.nix ];
          };
      };

      overlays = {
        list = overlayList;
        default = composedOverlay;
      };

      tests = forAllSystems (
        system:
        vpsadminos.lib.testFramework.mkTests {
          inherit system;
          pkgsPath = nixpkgs.outPath;
          testsRoot = ./tests;
        }
      );

      testsMeta = forAllSystems (
        system:
        vpsadminos.lib.testFramework.mkTestsMeta {
          inherit system;
          pkgsPath = nixpkgs.outPath;
          testsRoot = ./tests;
        }
      );

      apps = forAllSystems (system: {
        notification-template-check = {
          type = "app";
          program = "${(notificationTemplateToolsFor system).checker}/bin/notification-template-check";
          meta.description = "Check vpsAdmin notification templates";
        };
        test-runner = {
          type = "app";
          program = "${vpsadminos.packages.${system}.test-runner}/bin/test-runner";
        };
      });

      packages = forAllSystems (system: {
        notification-template-check = (notificationTemplateToolsFor system).checker;
        test-runner = vpsadminos.packages.${system}.test-runner;
      });

      checks = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          vpsadminPkgs = import nixpkgs {
            inherit system;
            overlays = [ composedOverlay ];
          };
          notificationTemplateTools = notificationTemplateToolsFor system;
          notificationTemplateOverride = pkgs.runCommand "notification-template-override" { } ''
            mkdir -p "$out/templates/daily_report"
            cp -a ${./api/notification_templates/templates/daily_report}/. \
              "$out/templates/daily_report/"
            chmod -R u+w "$out/templates"
            printf '%s\n' 'Overridden daily report' \
              > "$out/templates/daily_report/email/en.subject.erb"
          '';
          effectiveNotificationTemplates = notificationTemplateTools.mkEffectivePackage {
            vpsadminPackage = vpsadminPkgs.vpsadmin-api;
            plugins = [ "outage_reports" ];
            source = notificationTemplateOverride;
          };
          replacementNotificationTemplates = notificationTemplateTools.mkEffectivePackage {
            vpsadminPackage = vpsadminPkgs.vpsadmin-api;
            plugins = [ "outage_reports" ];
            source = notificationTemplateOverride;
            mode = "replace";
          };
          replacementDatabaseModule = {
            system.stateVersion = "24.11";
            vpsadmin.api = {
              enable = true;
              notificationTemplates = {
                mode = "replace";
                source = notificationTemplateOverride;
              };
            };
          };
          replacementDatabaseConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.nixos-modules
              replacementDatabaseModule
            ];
          };
          invalidReplacementDatabaseConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.nixos-modules
              replacementDatabaseModule
              {
                vpsadmin.databaseSetup.installDefaultNotificationTemplates = true;
              }
            ];
          };
          findNotificationTemplateDatabaseAssertion =
            configuration:
            nixpkgs.lib.findFirst (
              assertion: nixpkgs.lib.hasInfix "installDefaultNotificationTemplates cannot be" assertion.message
            ) null configuration.config.assertions;
          replacementDatabaseAssertion = findNotificationTemplateDatabaseAssertion replacementDatabaseConfiguration;
          invalidReplacementDatabaseAssertion = findNotificationTemplateDatabaseAssertion invalidReplacementDatabaseConfiguration;
          systemConfigurationUrl = "https://github.com/example/configuration/commit/";
          webuiConfiguration = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.nixos-modules
              {
                vpsadmin.webui = {
                  enable = true;
                  domain = "webui.example.test";
                  api.externalUrl = "https://api.example.test";
                  api.internalUrl = "http://api.example.test";
                  productionEnvironmentId = 1;
                  softwareRevisionLinks.system_configuration = systemConfigurationUrl;
                };
              }
            ];
          };
          actual = webuiConfiguration.config.vpsadmin.webui.softwareRevisionLinks;
          expected = {
            nixpkgs = "https://github.com/NixOS/nixpkgs/commit/";
            system_configuration = systemConfigurationUrl;
            vpsadmin = "https://github.com/vpsfreecz/vpsadmin/commit/";
            vpsadminos = "https://github.com/vpsfreecz/vpsadminos/commit/";
          };
        in
        {
          effective-notification-templates = pkgs.runCommand "effective-notification-templates" { } ''
            grep -Fx 'Overridden daily report' \
              ${effectiveNotificationTemplates}/templates/daily_report/email/en.subject.erb
            test -e \
              ${effectiveNotificationTemplates}/templates/outage_report_generic/email/en.text.erb
            test ! -e \
              ${effectiveNotificationTemplates}/templates/payments_overview
            touch "$out"
          '';

          replacement-notification-templates = pkgs.runCommand "replacement-notification-templates" { } ''
            grep -Fx 'Overridden daily report' \
              ${replacementNotificationTemplates}/templates/daily_report/email/en.subject.erb
            test ! -e \
              ${replacementNotificationTemplates}/templates/outage_report_generic
            test ! -e \
              ${replacementNotificationTemplates}/templates/request_update_user
            test "$(find ${replacementNotificationTemplates}/templates \
              -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 1
            touch "$out"
          '';

          replacement-notification-templates-module =
            assert nixpkgs.lib.assertMsg (replacementDatabaseAssertion != null) ''
              The replacement notification template database assertion must be
              present in the test configuration
            '';
            assert nixpkgs.lib.assertMsg
              (
                !replacementDatabaseConfiguration.config.vpsadmin.databaseSetup.installDefaultNotificationTemplates
              )
              ''
                Replacement notification templates must disable built-in template
                installation by default
              '';
            assert nixpkgs.lib.assertMsg replacementDatabaseAssertion.assertion ''
              Replacement notification templates must permit the default
              built-in template installation setting
            '';
            assert nixpkgs.lib.assertMsg (invalidReplacementDatabaseAssertion != null) ''
              The contradictory replacement notification template database
              assertion must be present in the test configuration
            '';
            assert nixpkgs.lib.assertMsg (!invalidReplacementDatabaseAssertion.assertion) ''
              Replacement notification templates must reject explicitly enabling
              built-in template installation
            '';
            pkgs.runCommand "replacement-notification-templates-module" { } ''
              touch "$out"
            '';

          notification-templates = notificationTemplateTools.mkPackage {
            pname = "vpsadmin-default-notification-templates";
            src = ./api/notification_templates/templates;
          };

          webui-software-revision-links =
            assert nixpkgs.lib.assertMsg (actual == expected) ''
              Extending vpsadmin.webui.softwareRevisionLinks must preserve the
              standard component links
            '';
            pkgs.runCommand "webui-software-revision-links" { } ''
              touch $out
            '';
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ composedOverlay ];
          };
          lib = pkgs.lib;
          libosctlNative = pkgs.stdenv.mkDerivation {
            pname = "libosctl-native-dev";
            version = vpsadminosVersion;
            src = vpsadminos.outPath + "/libosctl";
            nativeBuildInputs = [ pkgs.ruby_vpsadminos ];

            dontConfigure = true;

            buildPhase = ''
              runHook preBuild
              cd ext/libosctl
              ruby extconf.rb
              make
              runHook postBuild
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p "$out/libosctl"
              cp native.so "$out/libosctl/native.so"
              runHook postInstall
            '';
          };

          enterRepoHook = componentPath: ''
            find_vpsadmin_repo_root() {
              dir="$PWD"

              while [ "$dir" != "/" ] && [ ! -f "$dir/flake.nix" ]; do
                dir="$(dirname "$dir")"
              done

              if [ ! -f "$dir/flake.nix" ]; then
                echo "Unable to locate vpsadmin flake root from $PWD" >&2
                return 1
              fi

              printf '%s\n' "$dir"
            }

            VPSADMIN_REPO_ROOT="$(find_vpsadmin_repo_root)" || exit 1
            export VPSADMIN_REPO_ROOT
            cd "$VPSADMIN_REPO_ROOT${lib.optionalString (componentPath != null) "/${componentPath}"}"
          '';

          devShellPrompt = promptName: ''
            export VPSADMIN_DEV_SHELL=1
            if [ -n "$PS1" ]; then
              export PS1="(dev:${promptName}) $PS1"
            fi
          '';

          mkRubyBundlerShell =
            {
              name,
              componentPath,
              packages,
              gemHome,
              promptName ? componentPath,
              rubyPackage ? pkgs.ruby_3_4,
              purityDisabled ? false,
              withLibosctlNative ? false,
              extraHook ? "",
            }:
            pkgs.mkShell {
              inherit name packages;

              shellHook = ''
                ${enterRepoHook componentPath}
                export GEM_HOME="${gemHome}"
                mkdir -p "$GEM_HOME"
                export GEM_PATH="$GEM_HOME:$PWD/lib"

                BUNDLE="$GEM_HOME/bin/bundle"

                [ ! -x "$BUNDLE" ] && ${rubyPackage}/bin/gem install bundler

                export BUNDLE_PATH="$GEM_HOME"
                export BUNDLE_GEMFILE="$PWD/Gemfile"
                export VPSADMINOS_PATH="''${VPSADMINOS_PATH:-${vpsadminos.outPath}}"
                export VPSADMINOS_GEM_VERSION="''${VPSADMINOS_GEM_VERSION:-${vpsadminosVersion}}"

              ''
              + lib.optionalString purityDisabled ''
                # Purity disabled because of prism gem, which has a native extension.
                # The extension has its header files in .gems, which gets stripped by
                # the cc wrapper in Nix. Without NIX_ENFORCE_PURITY=0, we get prism.h
                # not found error.
              ''
              + ''
                ${if purityDisabled then "NIX_ENFORCE_PURITY=0 " else ""}$BUNDLE install

              ''
              + lib.optionalString withLibosctlNative ''
                export RUBYLIB="${libosctlNative}''${RUBYLIB:+:$RUBYLIB}"
              ''
              + ''
                export RUBYOPT=-rbundler/setup
                export PATH="$(ruby -e 'puts Gem.bindir'):$PATH"
              ''
              + devShellPrompt promptName
              + extraHook;
            };

          mkComposerShell =
            {
              name,
              componentPath,
              packages,
              promptName ? componentPath,
              extraHook ? "",
            }:
            pkgs.mkShell {
              inherit name packages;

              shellHook = ''
                ${enterRepoHook componentPath}
              ''
              + devShellPrompt promptName
              + extraHook;
            };

          consoleRouterShell = mkRubyBundlerShell {
            name = "vpsadmin-console-router";
            componentPath = "console_router";
            packages = with pkgs; [
              git
              nodePackages.npm
              ruby_3_4
            ];
            gemHome = "$PWD/.gems";
            promptName = "console-router";
          };

          vpsadminShell = pkgs.mkShell {
            name = "vpsadmin";
            packages = with pkgs; [
              bundix
              git
              gettext
              libffi
              ncurses
              ruby_3_4
              zlib
              mariadb
              mariadb-connector-c
              nixfmt
              nixfmt-tree
              php83Packages.php-cs-fixer
            ];

            shellHook = ''
              ${enterRepoHook null}
              export GEM_HOME="$(pwd)/.gems"
              mkdir -p "$GEM_HOME"
              export RUBOCOP_CACHE_ROOT="$(pwd)/.rubocop_cache"
              export PATH="$(ruby -e 'puts Gem.bindir'):$PATH"
              export RUBYLIB="$GEM_HOME"
              export VPSADMINOS_PATH="''${VPSADMINOS_PATH:-${vpsadminos.outPath}}"
              export VPSADMINOS_GEM_VERSION="''${VPSADMINOS_GEM_VERSION:-${vpsadminosVersion}}"
              gem install --no-document bundler

              # Purity disabled because of prism gem, which has a native extension.
              # The extension has its header files in .gems, which gets stripped but
              # cc wrapper in Nix. Without NIX_ENFORCE_PURITY=0, we get prism.h not found
              # error.
              NIX_ENFORCE_PURITY=0 bundle install
            ''
            + devShellPrompt "vpsadmin";
          };
        in
        {
          default = vpsadminShell;
          vpsadmin = vpsadminShell;

          api = mkRubyBundlerShell {
            name = "vpsadmin-api";
            componentPath = "api";
            packages = with pkgs; [
              git
              mariadb
              mariadb-connector-c
              ruby_3_4
            ];
            gemHome = "$PWD/.gems";
            purityDisabled = true;
          };

          webui = mkComposerShell {
            name = "vpsadmin-webui";
            componentPath = "webui";
            packages = with pkgs; [
              gettext
              nixfmt
              php
              phpPackages.composer
            ];
            extraHook = ''
              export PATH="$(composer global config bin-dir --absolute):$PATH"
              composer global require svanderburg/composer2nix
            '';
          };

          client = mkRubyBundlerShell {
            name = "vpsadmin-client";
            componentPath = "client";
            packages = with pkgs; [
              ruby_3_4
              git
              zlib
              openssl
              ncurses
            ];
            gemHome = "/tmp/dev-ruby-gems";
          };

          "console-router" = consoleRouterShell;
          console_router = consoleRouterShell;

          nodectl = mkRubyBundlerShell {
            name = "nodectl";
            componentPath = "nodectl";
            packages = with pkgs; [
              git
              libffi
              mariadb-connector-c
              ncurses
              openssl
              ruby_vpsadminos
              zlib
            ];
            rubyPackage = pkgs.ruby_vpsadminos;
            gemHome = "/tmp/dev-ruby-gems";
          };

          nodectld = mkRubyBundlerShell {
            name = "nodectld";
            componentPath = "nodectld";
            packages = with pkgs; [
              git
              libffi
              mariadb-connector-c
              ncurses
              openssh
              openssl
              ruby_vpsadminos
              zlib
            ];
            rubyPackage = pkgs.ruby_vpsadminos;
            gemHome = "/tmp/dev-ruby-gems";
            withLibosctlNative = true;
            extraHook = ''
              run-nodectld() {
                bundle exec bin/nodectld --no-wrapper "$@"
              }
            '';
          };

          libnodectld = mkRubyBundlerShell {
            name = "libnodectld";
            componentPath = "libnodectld";
            packages = with pkgs; [
              ruby_vpsadminos
              git
              libffi
              zlib
              openssl
              ncurses
              mariadb
              mariadb-connector-c
              bind
            ];
            rubyPackage = pkgs.ruby_vpsadminos;
            gemHome = "/tmp/dev-ruby-gems";
            withLibosctlNative = true;
          };
        }
      );
    };
}
