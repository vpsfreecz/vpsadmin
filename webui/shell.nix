let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "vpsadmin-webui";

  buildInputs = [
    pkgs.phpPackages.composer
  ];
}
