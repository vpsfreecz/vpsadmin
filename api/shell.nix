let
  pkgs = import <nixpkgs> { };
  stdenv = pkgs.stdenv;

in
stdenv.mkDerivation rec {
  name = "vpsadmin-api";

  buildInputs = with pkgs; [
    git
    mariadb
    mariadb-connector-c
    ruby_3_3
  ];

  shellHook = ''
    export GEM_HOME="$PWD/.gems"
    mkdir -p "$GEM_HOME"
    export GEM_PATH="$GEM_HOME:$PWD/lib"

    BUNDLE="$GEM_HOME/bin/bundle"

    [ ! -x "$BUNDLE" ] && ${pkgs.ruby}/bin/gem install bundler

    export BUNDLE_PATH="$GEM_HOME"
    export BUNDLE_GEMFILE="$PWD/Gemfile"

    # Purity disabled because of prism gem, which has a native extension.
    # The extension has its header files in .gems, which gets stripped but
    # cc wrapper in Nix. Without NIX_ENFORCE_PURITY=0, we get prism.h not found
    # error.
    NIX_ENFORCE_PURITY=0 $BUNDLE install

    export RUBYOPT=-rbundler/setup
    export PATH="$(ruby -e 'puts Gem.bindir'):$PATH"
  '';
}
