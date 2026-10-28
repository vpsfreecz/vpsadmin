{
  lib,
  stdenv,
  fetchurl,
  defaultGemConfig,
  gnumake,
  bundlerEnv,
  ruby,
  vpsadmin-source,
}@args:
import ./common.nix args { name = "api"; }
