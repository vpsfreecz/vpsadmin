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
      flakeRevision = nixpkgs.lib.removeSuffix "-dirty" (self.rev or self.dirtyRev);
      overlayList = import ./nixos/overlays/default.nix {
        vpsadminRev = flakeRevision;
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
    in
    {
      nixosModules = {
        nixos-modules =
          { ... }:
          {
            _module.args = {
              inherit vpsadminos;
              vpsadminRev = flakeRevision;
            };
            imports = [ ./nixos/modules/nixos-modules.nix ];
          };
        vpsadminos-modules =
          { ... }:
          {
            _module.args = {
              inherit vpsadminos;
              vpsadminRev = flakeRevision;
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
          suiteArgs = {
            vpsadminosPath = vpsadminos.outPath;
          };
        }
      );

      testsMeta = forAllSystems (
        system:
        vpsadminos.lib.testFramework.mkTestsMeta {
          inherit system;
          pkgsPath = nixpkgs.outPath;
          testsRoot = ./tests;
          suiteArgs = {
            vpsadminosPath = vpsadminos.outPath;
          };
        }
      );

      apps = forAllSystems (system: {
        test-runner = {
          type = "app";
          program = "${vpsadminos.packages.${system}.test-runner}/bin/test-runner";
        };
      });

      packages = forAllSystems (system: {
        test-runner = vpsadminos.packages.${system}.test-runner;
      });

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ composedOverlay ];
          };
          lib = pkgs.lib;

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

              ''
              + lib.optionalString purityDisabled ''
                # Purity disabled because of prism gem, which has a native extension.
                # The extension has its header files in .gems, which gets stripped by
                # the cc wrapper in Nix. Without NIX_ENFORCE_PURITY=0, we get prism.h
                # not found error.
              ''
              + ''
                ${if purityDisabled then "NIX_ENFORCE_PURITY=0 " else ""}$BUNDLE install

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
              libffi
              ncurses
              ruby_3_4
              zlib
              mariadb
              mariadb-connector-c
              nixfmt-rfc-style
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
              nixfmt-rfc-style
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
              zlib
              openssl
              ncurses
              mariadb
              mariadb-connector-c
            ];
            rubyPackage = pkgs.ruby_vpsadminos;
            gemHome = "/tmp/dev-ruby-gems";
          };
        }
      );
    };
}
