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
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              bundix
              git
              libffi
              ncurses
              ruby
              zlib
              mariadb
              mariadb-connector-c
              nixfmt-rfc-style
              nixfmt-tree
              php83Packages.php-cs-fixer
            ];

            shellHook = ''
              export GEM_HOME="$(pwd)/.gems"
              export RUBOCOP_CACHE_ROOT="$(pwd)/.rubocop_cache"
              export PATH="$(ruby -e 'puts Gem.bindir'):$PATH"
              export RUBYLIB="$GEM_HOME"
              export PS1="(vpsadmin-dev) $PS1"
              gem install --no-document bundler

              # Purity disabled because of prism gem, which has a native extension.
              # The extension has its header files in .gems, which gets stripped but
              # cc wrapper in Nix. Without NIX_ENFORCE_PURITY=0, we get prism.h not found
              # error.
              NIX_ENFORCE_PURITY=0 bundle install
            '';
          };
        }
      );
    };
}
