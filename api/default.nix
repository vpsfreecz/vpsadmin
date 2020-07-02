let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "vpsadmin-api";

  buildInputs = [
    pkgs.ruby
    pkgs.git
    pkgs.mariadb
    pkgs.mariadb-connector-c
  ];

  shellHook = ''
    export GEM_HOME="$PWD/.gems"
    mkdir -p "$GEM_HOME"
    export GEM_PATH="$GEM_HOME:$PWD/lib"
    export PATH="$GEM_HOME/bin:$PATH"

    BUNDLE="$GEM_HOME/bin/bundle"

    [ ! -x "$BUNDLE" ] && ${pkgs.ruby}/bin/gem install bundler

    export BUNDLE_PATH="$GEM_HOME"
    export BUNDLE_GEMFILE="$PWD/Gemfile"

    $BUNDLE install

    export RUBYOPT=-rbundler/setup
  '';
}
