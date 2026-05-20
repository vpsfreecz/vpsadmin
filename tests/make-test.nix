testFn:
{ vpsadminosPath, ... }@args:
let
  ciTags = import ./ci-tags.nix;
  unique =
    list: builtins.foldl' (acc: item: if builtins.elem item acc then acc else acc ++ [ item ]) [ ] list;
  addScriptTags =
    testName:
    builtins.mapAttrs (
      scriptName: script:
      script
      // {
        tags = unique ((script.tags or [ ]) ++ (ciTags.scriptTags testName scriptName));
      }
    );
  taggedTestFn =
    fnArgs:
    let
      testAttrs = testFn fnArgs;
      testName = testAttrs.name;
    in
    testAttrs
    // {
      tags = unique ((testAttrs.tags or [ ]) ++ (ciTags.testTags testName));
    }
    // (
      if builtins.hasAttr "testScripts" testAttrs then
        {
          testScripts = addScriptTags testName testAttrs.testScripts;
        }
      else
        { }
    );
  upstream = import (vpsadminosPath + "/tests/make-test.nix") taggedTestFn;
  mergedExtraArgs = {
    vpsadminos = vpsadminosPath;
  }
  // (args.extraArgs or { });
  argsWithExtra = args // {
    extraArgs = mergedExtraArgs;
  };
in
upstream argsWithExtra
