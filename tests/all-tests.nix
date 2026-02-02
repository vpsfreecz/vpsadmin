{
  pkgs ? <nixpkgs>,
  system ? builtins.currentSystem,
}:
let
  nixpkgs = import pkgs { };
  lib = nixpkgs.lib;
  testLib = import <vpsadminos/test-runner/nix/lib.nix> {
    inherit pkgs system lib;
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
