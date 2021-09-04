{ lib, stdenv, fetchurl, bundlerEnv, ruby, makeWrapper }:
let
  version = "dev";

  rubyEnv = bundlerEnv {
    name = "vpsadmin-console-router-env-${version}";

    inherit ruby;
    gemdir = ./.;
  };

  filterRepository = path: type:
    !(type == "directory" && baseNameOf path == ".gems")
    &&
    !(type == "directory" && baseNameOf path == ".git");

in stdenv.mkDerivation rec {
  pname = "vpsadmin-console-router";
  inherit version;

  src = builtins.filterSource filterRepository <vpsadmin>;

  buildInputs = [ rubyEnv rubyEnv.wrappedRuby rubyEnv.bundler ];

  buildPhase = ''
    :
  '';

  installPhase = ''
    mkdir -p $out/console_router
    cp -a console_router/. $out/console_router/

    for i in config; do
        rm -rf $out/console_router/$i
        ln -sf /run/vpsadmin/console_router/$i $out/console_router/$i
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
