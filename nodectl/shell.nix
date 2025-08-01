let
  pkgs = import <nixpkgs> { overlays = (import <vpsadminos/os/overlays>); };
  stdenv = pkgs.stdenv;

in
stdenv.mkDerivation rec {
  name = "nodectl";

  buildInputs = with pkgs; [
    git
    libffi
    mariadb-connector-c
    ncurses
    openssl
    ruby
    zlib
  ];

  shellHook = ''
    mkdir -p /tmp/dev-ruby-gems
    export GEM_HOME="/tmp/dev-ruby-gems"
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
