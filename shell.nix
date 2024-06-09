let
  pkgs = import <nixpkgs> {
    overlays = [
      (import ../vpsadminos/os/overlays/ruby.nix)
    ];
  };
  stdenv = pkgs.stdenv;

in stdenv.mkDerivation rec {
  name = "vpsadmin";

  buildInputs = with pkgs; [
    bundix
    git
    ncurses
    ruby
    zlib
    mariadb
    mariadb-connector-c
    phpPackages.php-cs-fixer
  ];

  shellHook = ''
    export GEM_HOME="$(pwd)/.gems"
    export PATH="$(ruby -e 'puts Gem.bindir'):$PATH"
    export RUBYLIB="$GEM_HOME"
    gem install --no-document bundler geminabox overcommit rake rubocop rubocop-rake

    # TODO: remove when geminabox is fixed, see https://github.com/geminabox/geminabox/pull/572
    gem install --no-document rubygems-generate_index
  '';
}
