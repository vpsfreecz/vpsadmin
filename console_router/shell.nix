let
  pkgs = import <nixpkgs> { };
  stdenv = pkgs.stdenv;

in
stdenv.mkDerivation rec {
  name = "vpsadmin-console-router";

  buildInputs = with pkgs; [
    git
    nodePackages.npm
    ruby
  ];

  shellHook = ''
    export GEM_HOME="$PWD/.gems"
    mkdir -p "$GEM_HOME"
    export GEM_PATH="$GEM_HOME:$PWD/lib"

    BUNDLE="$GEM_HOME/bin/bundle"

    [ ! -x "$BUNDLE" ] && ${pkgs.ruby}/bin/gem install bundler

    export BUNDLE_PATH="$GEM_HOME"
    export BUNDLE_GEMFILE="$PWD/Gemfile"

    $BUNDLE install

    export RUBYOPT=-rbundler/setup
    export PATH="$(ruby -e 'puts Gem.bindir'):$PATH"
  '';
}
