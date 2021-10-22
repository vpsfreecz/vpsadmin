{ lib, stdenv, vpsadminPath ? <vpsadmin> }:
let
  filterRepository = path: type:
    !(type == "directory" && baseNameOf path == ".gems")
    &&
    !(type == "directory" && baseNameOf path == ".git");

  copiedRepo =
    if lib.isStorePath vpsadminPath then
      vpsadminPath
    else
      builtins.filterSource filterRepository vpsadminPath;

  revisionFile = "${copiedRepo}/.git-revision";

  hasRevisionFile = builtins.pathExists revisionFile;

  readVersion = lib.strings.sanitizeDerivationName (
    builtins.replaceStrings [ "\n" ] [ "" ] (builtins.readFile revisionFile)
  );

  version = if hasRevisionFile then readVersion else "dev";

in stdenv.mkDerivation rec {
  pname = "vpsadmin-source";
  inherit version;

  src = copiedRepo;

  buildPhase = ''
    :
  '';

  installPhase = ''
    cp -a ./. $out/

    ${lib.optionalString hasRevisionFile ''
    for v in api console_router webui ; do
      cp ${revisionFile} $out/$v/.git-revision
    done
    ''}
  '';

  meta = with lib; {
    homepage = "https://github.com/vpsfreecz/vpsadmin";
    platforms = platforms.linux;
    maintainers = [];
    license = licenses.gpl2;
  };
}
