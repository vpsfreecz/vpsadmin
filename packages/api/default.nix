{ lib, stdenv, fetchurl, bundlerEnv, ruby, makeWrapper }:
let
  version = "dev";

  rubyEnv = bundlerEnv {
    name = "vpsadmin-api-env-${version}";

    inherit ruby;
    gemdir = ./.;
  };

  filterRepository = path: type:
    !(type == "directory" && baseNameOf path == ".gems")
    &&
    !(type == "directory" && baseNameOf path == ".git");

in stdenv.mkDerivation rec {
  pname = "vpsadmin-api";
  inherit version;

  src = builtins.filterSource filterRepository <vpsadmin>;

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
