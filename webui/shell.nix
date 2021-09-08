let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "vpsadmin-webui";

  buildInputs = with pkgs; [
    php
    phpPackages.composer
  ];

  shellHook = ''
    export PATH="$(composer global config bin-dir --absolute):$PATH"
    composer global require svanderburg/composer2nix
  '';
}
