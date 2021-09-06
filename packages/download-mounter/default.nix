{ lib, stdenv, fetchurl, bundlerEnv, ruby, vpsadmin-source }:
let
  version = vpsadmin-source.version;

  rubyEnv = bundlerEnv {
    name = "vpsadmin-download-mounter-env-${version}";

    inherit ruby;
    gemdir = ./.;
  };

in stdenv.mkDerivation rec {
  pname = "vpsadmin-download-mounter";
  inherit version;

  src = vpsadmin-source;

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
