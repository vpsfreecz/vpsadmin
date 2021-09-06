{ lib, stdenv, fetchurl, bundlerEnv, ruby, vpsadmin-source }:
let
  version = vpsadmin-source.version;

  rubyEnv = bundlerEnv {
    name = "vpsadmin-api-env-${version}";

    inherit ruby;
    gemdir = ./.;
  };

in stdenv.mkDerivation rec {
  pname = "vpsadmin-api";
  inherit version;

  src = vpsadmin-source;

  buildInputs = [ rubyEnv rubyEnv.wrappedRuby rubyEnv.bundler ];

  buildPhase = ''
    :
  '';

  installPhase = ''
    mkdir -p $out/api $out/plugins
    cp -a api/. $out/api/
    cp -a plugins/. $out/plugins/

    for i in config plugins; do
        rm -rf $out/api/$i
        ln -sf /run/vpsadmin/api/$i $out/api/$i
    done

    ln -sf ${rubyEnv} $out/ruby-env
  '';

  meta = with lib; {
    homepage = "https://github.com/vpsfreecz/vpsadmin";
    platforms = platforms.linux;
    maintainers = [];
    license = licenses.gpl2;
  };
}
