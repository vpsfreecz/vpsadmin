{
  pkgs ? <nixpkgs>,
  system ? builtins.currentSystem,
}:
let
  nixpkgs = import pkgs { };
  lib = nixpkgs.lib;
  testLib = import ../../vpsadminos/test-runner/nix/lib.nix {
    inherit pkgs system lib;
    suitePath = ./suite;
  };
in
testLib.makeTests [
  "vpsadmin/services-up"
]
