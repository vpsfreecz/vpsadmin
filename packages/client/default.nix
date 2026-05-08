{
  lib,
  stdenv,
  bundlerEnv,
  makeWrapper,
  ruby,
  vpsadmin-source,
}:
let
  version = vpsadmin-source.version;

  rubyEnv = bundlerEnv {
    name = "vpsadmin-client-env-${version}";

    inherit ruby;
    gemdir = ./.;
  };

in
stdenv.mkDerivation {
  pname = "vpsadmin-client";
  inherit version;

  src = vpsadmin-source;

  nativeBuildInputs = [
    makeWrapper
  ];

  buildInputs = [
    rubyEnv
    rubyEnv.wrappedRuby
  ];

  buildPhase = ''
    :
  '';

  installPhase = ''
    mkdir -p $out/client $out/bin
    cp -a client/bin client/lib $out/client/
    cp client/CHANGELOG client/LICENSE client/README.md $out/client/

    makeWrapper ${rubyEnv.wrappedRuby}/bin/ruby $out/bin/vpsadminctl \
      --add-flags "$out/client/bin/vpsadminctl" \
      --prefix RUBYLIB : "$out/client/lib"

    ln -sf ${rubyEnv} $out/ruby-env
  '';

  meta = with lib; {
    description = "CLI client for vpsAdmin API";
    homepage = "https://github.com/vpsfreecz/vpsadmin";
    license = licenses.gpl3;
    maintainers = [ maintainers.sorki ];
    platforms = platforms.unix;
  };
}
