{ lib, bundlerApp }:

bundlerApp {
  pname = "nodectl";
  gemdir = ./.;
  exes = [ "nodectl" ];

  meta = with lib; {
    description = "";
    homepage    = https://github.com/vpsfreecz/vpsadmin;
    license     = licenses.gpl3;
    maintainers = [ maintainers.sorki ];
    platforms   = platforms.unix;
  };
}
