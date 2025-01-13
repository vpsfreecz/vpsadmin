let
  pkgs = import <nixpkgs> {};
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "nodectld";

  buildInputs = with pkgs; [
    ruby_3_3
    git
    zlib
    openssl
    ncurses
    mariadb-connector-c
    openssh
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

    run-nodectld() {
      bundle exec bin/nodectld --no-wrapper "$@"
    }
  '';
}
