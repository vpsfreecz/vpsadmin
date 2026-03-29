{
  pkgs ? <nixpkgs>,
  system ? builtins.currentSystem,
  suiteArgs ? { },
  configuration ? null,
  testConfig ? { },
}:
let
  vpsadminosPath = suiteArgs.vpsadminosPath or (throw "suiteArgs.vpsadminosPath is required");
  nixpkgs = import pkgs { inherit system; };
  lib = nixpkgs.lib;
  testLib = import (vpsadminosPath + "/test-runner/nix/lib.nix") {
    inherit
      pkgs
      system
      lib
      suiteArgs
      configuration
      testConfig
      ;
    suitePath = ./suite;
  };
in
testLib.makeTests [
  "v4/cluster/1-node"
  "v4/cluster/2-node"
  "v4/node/register"
  "v4/vps/create"
  "v4/vps/migrate"
  "vpsadmin/services-up"
]
