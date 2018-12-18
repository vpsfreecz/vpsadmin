{ pkgs ? import <nixpkgs> {} }:
let
  f =
    { buildMix }:
    buildMix {
      name = "core";
      version = "0.1.0";
      src = ./.;
      beamDeps = [];
      shellHook = ''
        export ERL_AFLAGS="-kernel shell_history enabled"
      '';
    };
  drv = pkgs.beam.packages.erlangR21.callPackage f {};

in drv
