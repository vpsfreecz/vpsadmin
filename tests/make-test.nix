testFn:
{ vpsadminosPath, ... }@args:
let
  upstream = import (vpsadminosPath + "/tests/make-test.nix") testFn;
  mergedExtraArgs = {
    vpsadminos = vpsadminosPath;
  }
  // (args.extraArgs or { });
  argsWithExtra = args // {
    extraArgs = mergedExtraArgs;
  };
in
upstream argsWithExtra
