{ lib, bundlerApp }:

bundlerApp {
  pname = "libnodectld";
  gemdir = ./.;

  meta = with lib; {
    description = "";
    homepage = "https://github.com/vpsfreecz/vpsadmin";
    license = licenses.gpl3;
    maintainers = [ ];
    platforms = platforms.unix;
  };
}
