{
  lib,
  stdenv,
  fetchurl,
  bundlerEnv,
  ruby,
  vpsadmin-source,
}@args:
import ./common.nix args { name = "database"; }
