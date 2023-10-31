{ lib, stdenv, fetchurl, bundlerEnv, ruby, vpsadmin-source }:
{ name }:
let
  version = vpsadmin-source.version;

  rubyEnv = bundlerEnv {
    name = "vpsadmin-${name}-env-${version}";

    inherit ruby;
    gemdir = ./.;
  };

in stdenv.mkDerivation rec {
  pname = "vpsadmin-${name}";
  inherit version;

  src = vpsadmin-source;

  buildInputs = [ rubyEnv rubyEnv.wrappedRuby rubyEnv.bundler ];

  buildPhase = ''
    :
  '';

  installPhase = ''
    mkdir -p $out/${name} $out/plugins
    cp -a api/. $out/${name}/
    cp -a plugins/. $out/plugins/

    for i in config plugins; do
        rm -rf $out/${name}/$i
        ln -sf /run/vpsadmin/${name}/$i $out/${name}/$i
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
