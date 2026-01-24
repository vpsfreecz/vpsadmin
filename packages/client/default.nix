{
  lib,
  bundlerApp,
  ruby,
}:

bundlerApp {
  pname = "vpsadmin-client";
  gemdir = ./.;
  exes = [ "vpsadminctl" ];
  inherit ruby;

  meta = with lib; {
    description = "CLI client for vpsAdmin API";
    homepage = "https://github.com/vpsfreecz/vpsadmin";
    license = licenses.gpl3;
    maintainers = [ maintainers.sorki ];
    platforms = platforms.unix;
  };
}
