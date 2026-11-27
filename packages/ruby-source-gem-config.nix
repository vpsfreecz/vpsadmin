{ lib }:

let
  mkSourceRoot = subdir: if subdir == "." then "source" else "source/${subdir}";

  mkGemConfig =
    {
      repoPath,
      gems,
    }:
    lib.mapAttrs (
      name:
      {
        version,
        gemDir ? name,
        extraConfig ? (_: { }),
      }:
      attrs:
      let
        sourceRoot = mkSourceRoot gemDir;
      in
      attrs
      // {
        inherit version;

        source = {
          type = "gem";
        };

        # Development dependencies must not become source gem candidates.
        src = builtins.filterSource (
          path: type: !(type == "directory" && baseNameOf path == ".gems")
        ) repoPath;
        dontBuild = false;

        unpackPhase = ''
          runHook preUnpack

          mkdir source
          cp -a "$src/." source/
          chmod -R u+w source
          sourceRoot=${sourceRoot}

          runHook postUnpack
        '';
      }
      // extraConfig attrs
    ) gems;

  mergeGemConfig =
    base: overrides:
    base
    // lib.mapAttrs (
      name: override: attrs:
      let
        baseAttrs = if base ? ${name} then attrs // base.${name} attrs else attrs;
      in
      baseAttrs // override baseAttrs
    ) overrides;
in
{
  inherit mkGemConfig mergeGemConfig;
}
