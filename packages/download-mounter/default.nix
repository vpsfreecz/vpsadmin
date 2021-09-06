{ lib, stdenv, fetchurl, bundlerEnv, ruby, makeWrapper }:
let
  version = "dev";

  rubyEnv = bundlerEnv {
    name = "vpsadmin-download-mounter-env-${version}";

    inherit ruby;
    gemdir = ./.;
  };

  filterRepository = path: type:
    !(type == "directory" && baseNameOf path == ".gems")
    &&
    !(type == "directory" && baseNameOf path == ".git");

in stdenv.mkDerivation rec {
  pname = "vpsadmin-download-mounter";
  inherit version;

  src = builtins.filterSource filterRepository <vpsadmin>;

  buildInputs = [ rubyEnv rubyEnv.wrappedRuby rubyEnv.bundler ];

  buildPhase = ''
    :
  '';

  installPhase = ''
    mkdir -p $out/download_mounter
    cp -a download_mounter/. $out/download_mounter/

    ln -sf ${rubyEnv} $out/ruby-env
  '';

  meta = with lib; {
    homepage = "https://github.com/vpsfreecz/vpsadmin";
    platforms = platforms.linux;
    maintainers = [];
    license = licenses.gpl2;
  };
}
