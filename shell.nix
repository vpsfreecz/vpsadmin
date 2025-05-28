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
    libffi
    ncurses
    ruby
    zlib
    mariadb
    mariadb-connector-c
    php83Packages.php-cs-fixer
  ];

  shellHook = ''
    export GEM_HOME="$(pwd)/.gems"
    export PATH="$(ruby -e 'puts Gem.bindir'):$PATH"
    export RUBYLIB="$GEM_HOME"
    gem install --no-document bundler

    # Purity disabled because of prism gem, which has a native extension.
    # The extension has its header files in .gems, which gets stripped but
    # cc wrapper in Nix. Without NIX_ENFORCE_PURITY=0, we get prism.h not found
    # error.
    NIX_ENFORCE_PURITY=0 bundle install
  '';
}
