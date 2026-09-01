{
  lib,
  stdenvNoCC,
  ruby_3_4,
  writeShellApplication,
}:
let
  checker = writeShellApplication {
    name = "notification-template-check";
    runtimeInputs = [ ruby_3_4 ];
    text = ''
      exec ruby -I${../../api/lib} ${./check.rb} "$@"
    '';
  };

  resolveSource = ''
    resolve_source() {
      if [ -d "$1/templates" ]; then
        printf '%s\n' "$1/templates"
      else
        printf '%s\n' "$1"
      fi
    }
  '';

  mkPackage =
    {
      src,
      pname ? "vpsadmin-notification-templates",
    }:
    stdenvNoCC.mkDerivation {
      inherit pname src;
      version = "1";
      nativeBuildInputs = [ checker ];

      dontConfigure = true;

      buildPhase = ''
        runHook preBuild
        notification-template-check "$src"
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        ${resolveSource}
        source_path="$(resolve_source "$src")"
        mkdir -p "$out/templates"
        cp -a "$source_path"/. "$out/templates/"
        runHook postInstall
      '';
    };

  mkEffectivePackage =
    {
      vpsadminPackage,
      plugins ? [ ],
      source,
      mode ? "overlay",
    }:
    assert lib.assertMsg (builtins.elem mode [
      "overlay"
      "replace"
    ]) "notification template mode must be either overlay or replace";
    stdenvNoCC.mkDerivation {
      pname = "vpsadmin-effective-notification-templates";
      version = "1";
      dontUnpack = true;
      nativeBuildInputs = [ checker ];

      installPhase = ''
        runHook preInstall
        ${resolveSource}
        mkdir -p "$out/templates"

        ${lib.optionalString (mode == "overlay") ''
          cp -a ${vpsadminPackage}/api/notification_templates/templates/. "$out/templates/"
          chmod -R u+w "$out/templates"

          for plugin_path in ${
            lib.escapeShellArgs (
              map (plugin: "${vpsadminPackage}/plugins/${plugin}/notification_templates/templates") plugins
            )
          }; do
            [ -d "$plugin_path" ] || continue

            for template_path in "$plugin_path"/*; do
              [ -d "$template_path" ] || continue
              template_name="$(basename "$template_path")"
              [ -e "$out/templates/$template_name" ] || \
                cp -a "$template_path" "$out/templates/"
            done

            chmod -R u+w "$out/templates"
          done
        ''}

        source_path="$(resolve_source ${lib.escapeShellArg (toString source)})"
        cp -a "$source_path"/. "$out/templates/"

        notification-template-check "$out/templates"
        runHook postInstall
      '';
    };
in
{
  inherit checker mkEffectivePackage mkPackage;
}
