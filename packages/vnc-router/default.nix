{
  lib,
  buildGoModule,
  vpsadmin-source,
}:
let
  version = vpsadmin-source.version;
in
buildGoModule {
  pname = "vpsadmin-vnc-router";
  inherit version;

  src = vpsadmin-source;
  modRoot = "./vnc_router";
  subPackages = [ "cmd/vnc_router" ];
  vendorHash = "sha256-wS86v/2FYkXoPn0LxYx/i+Oycwf4QmBIGjUdlQnRrKo=";

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    homepage = "https://github.com/vpsfreecz/vpsadmin";
    platforms = platforms.linux;
    maintainers = [ ];
    license = licenses.gpl2;
  };
}
