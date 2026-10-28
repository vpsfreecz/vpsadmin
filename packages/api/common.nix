{
  lib,
  stdenv,
  fetchurl,
  defaultGemConfig,
  gnumake,
  bundlerEnv,
  ruby,
  vpsadmin-source,
}:
{ name }:
let
  version = vpsadmin-source.version;

  rubyEnv = bundlerEnv {
    name = "vpsadmin-${name}-env-${version}";

    inherit ruby;
    gemdir = ./.;
    gemConfig =
      defaultGemConfig
      //
        lib.genAttrs
          [ "haveapi" "haveapi-client" "haveapi-go-client" "haveapi-rust-client" "haveapi-typescript-client" ]
          (
            gemName: attrs:
            let
              inherited = (defaultGemConfig.${gemName} or (_: { })) attrs;
              configured = attrs // inherited;
            in
            inherited
            // lib.optionalAttrs (attrs.source.type == "git") {
              # Keep the normal Nix Git installer, supplying its missing nested
              # gemspec discovery option only during this gem's installation.
              preInstall = (configured.preInstall or "") + ''
                haveapi_rubyopt_set="''${RUBYOPT+x}"
                haveapi_saved_rubyopt="''${RUBYOPT-}"
                export RUBYOPT="-r${./haveapi-git-gemspec-glob.rb}''${RUBYOPT:+ $RUBYOPT}"
              '';
              postInstall = ''
                if [ "$haveapi_rubyopt_set" = x ]; then
                  export RUBYOPT="$haveapi_saved_rubyopt"
                else
                  unset RUBYOPT
                fi
                unset haveapi_rubyopt_set haveapi_saved_rubyopt

                # Shared Git checkouts must agree across sibling gem outputs.
                # These staging indexes contain build-specific filesystem times.
                haveapi_install_path="$(cat "$out/nix-support/gem-meta/install-path")"
                if [ "$haveapi_install_path" != "$GEM_HOME/bundler/gems/haveapi-${
                  builtins.substring 0 12 attrs.source.rev
                }" ]; then
                  echo "Unexpected HaveAPI Git install path" >&2
                  exit 1
                fi
                haveapi_cache_indexes=("$GEM_HOME"/cache/bundler/git/haveapi-*/index)
                if [ "''${#haveapi_cache_indexes[@]}" -ne 1 ] || ! [ -f "''${haveapi_cache_indexes[0]}" ] || ! [ -f "$haveapi_install_path/.git/index" ]; then
                  echo "Unexpected HaveAPI Git staging indexes" >&2
                  exit 1
                fi
                rm -- "$haveapi_install_path/.git/index" "''${haveapi_cache_indexes[0]}"
                unset haveapi_install_path haveapi_cache_indexes
              ''
              + (configured.postInstall or "");
              # Prepare identical docs/serialized metadata in all sibling outputs
              # before buildRubyGem stages their shared whole-repository source.
              preBuild = (configured.preBuild or "") + ''
                ${gnumake}/bin/make doc
              '';
            }
          );
  };

in
stdenv.mkDerivation rec {
  pname = "vpsadmin-${name}";
  inherit version;

  src = vpsadmin-source;

  buildInputs = [
    rubyEnv
    rubyEnv.wrappedRuby
    rubyEnv.bundler
  ];

  buildPhase = ''
    :
  '';

  installPhase = ''
    mkdir -p $out/${name} $out/plugins
    cp -a api/. $out/${name}/
    cp -a plugins/. $out/plugins/

    for i in config plugins; do
        rm -rf $out/${name}/$i
        ln -sf /run/vpsadmin/${name}/$i $out/${name}/$i
    done

    ln -sf ${rubyEnv} $out/ruby-env
    ln -sf ${rubyEnv.wrappedRuby} $out/ruby-env-wrapped
  '';

  meta = with lib; {
    homepage = "https://github.com/vpsfreecz/vpsadmin";
    platforms = platforms.linux;
    maintainers = [ ];
    license = licenses.gpl2;
  };
}
