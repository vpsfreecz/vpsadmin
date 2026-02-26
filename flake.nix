{
  description = "vpsAdmin (NixOS/vpsAdminOS modules and packages)";

  inputs = {
    vpsadminos.url = "github:vpsfreecz/vpsadminos/2026-02-19-flakes";
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
      overlayList = import ./nixos/overlays/default.nix;
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
            _module.args.vpsadminos = vpsadminos;
            imports = [ ./nixos/modules/nixos-modules.nix ];
          };
        vpsadminos-modules =
          { ... }:
          {
            _module.args.vpsadminos = vpsadminos;
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
    };
}
