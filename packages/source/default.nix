{
  lib,
  stdenv,
  vpsadminPath ? <vpsadmin>,
  vpsadminRev,
}:
let
  filterRepository =
    path: type:
    !(type == "directory" && baseNameOf path == ".gems")
    && !(type == "directory" && baseNameOf path == ".git")
    && !(type == "directory" && baseNameOf path == "result")
    && !(type == "directory" && baseNameOf path == "tests");

  copiedRepo =
    if lib.isStorePath vpsadminPath then
      vpsadminPath
    else
      builtins.filterSource filterRepository vpsadminPath;

  revision = builtins.replaceStrings [ "\n" ] [ "" ] (toString vpsadminRev);

  version = lib.strings.sanitizeDerivationName revision;

in
stdenv.mkDerivation rec {
  pname = "vpsadmin-source";
  inherit version;

  src = copiedRepo;

  buildPhase = ''
    :
  '';

  installPhase = ''
    cp -a ./. $out/

    for v in api console_router webui ; do
      printf '%s\n' '${revision}' > $out/$v/.git-revision
    done
  '';

  meta = with lib; {
    homepage = "https://github.com/vpsfreecz/vpsadmin";
    platforms = platforms.linux;
    maintainers = [ ];
    license = licenses.gpl2;
  };
}
