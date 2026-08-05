{
  vpsadminRev,
  vpsadminosPath ? null,
}:
[
  (
    self: super:
    let
      ruby = super.ruby_3_4;
      lib = super.lib;
      rubyGemConfig = import ../../packages/ruby-source-gem-config.nix {
        inherit lib;
      };
      vpsadminVersion = lib.removeSuffix "\n" (builtins.readFile ../../VERSION);
      # Connector/C 3.3.5 can segfault on malformed result metadata (CONC-709).
      # Remove this source override once pinned nixpkgs has version 3.4.9 or newer.
      mariadbConnector =
        if lib.versionAtLeast super.mariadb-connector-c.version "3.4.9" then
          super.mariadb-connector-c
        else
          super.mariadb-connector-c.overrideAttrs (oldAttrs: {
            version = "3.4.9";
            src = super.fetchFromGitHub {
              owner = "mariadb-corporation";
              repo = "mariadb-connector-c";
              rev = "v3.4.9";
              hash = "sha256-dcAEIjlp7M3NWXSI5FzL78tSdP39P8BC/C4Huci95Dw=";
            };
            patches = [ ];
            postPatch = oldAttrs.postPatch + ''
              substituteInPlace mariadb_config/mariadb_config.c.in \
                --replace-fail 'printf(CFLAGS, installation_dir, installation_dir);' 'printf("%s", CFLAGS);' \
                --replace-fail 'printf(INCLUDE, installation_dir, installation_dir);' 'printf("%s", INCLUDE);' \
                --replace-fail 'printf(LIBS, installation_dir);' 'printf("%s", LIBS);' \
                --replace-fail 'printf(PLUGIN_DIR, installation_dir);' 'printf("%s", PLUGIN_DIR);'
            '';
          });
      vpsadminosVersion =
        if vpsadminosPath == null then
          null
        else
          "${lib.removeSuffix "\n" (builtins.readFile (vpsadminosPath + "/.version"))}.0";
      nodeSourceGemConfig =
        let
          vpsadminosGemEnv =
            _attrs:
            lib.optionalAttrs (vpsadminosVersion != null) {
              VPSADMINOS_GEM_VERSION = vpsadminosVersion;
            };
        in
        rubyGemConfig.mkGemConfig {
          repoPath = ../../.;
          gems = {
            libnodectld = {
              version = vpsadminVersion;
              extraConfig = vpsadminosGemEnv;
            };
            nodectl = {
              version = vpsadminVersion;
              extraConfig = vpsadminosGemEnv;
            };
            nodectld = {
              version = vpsadminVersion;
              extraConfig = vpsadminosGemEnv;
            };
          };
        }
        // lib.optionalAttrs (vpsadminosPath != null) (
          rubyGemConfig.mkGemConfig {
            repoPath = vpsadminosPath;
            gems = {
              libosctl.version = vpsadminosVersion;
              osctl.version = vpsadminosVersion;
              osctl-exportfs.version = vpsadminosVersion;
            };
          }
        );
      nodeMysql2GemConfig = {
        mysql2 = attrs: {
          dontBuild = false;
          buildInputs = [
            mariadbConnector
            super.zlib
            super.openssl
          ];
          # mysql2 does not clear Connector/C 3.4's default certificate
          # verification for ssl_mode: :disabled. Remove this patch when a
          # mysql2 release makes the MariaDB compatibility path do so.
          patches = (attrs.patches or [ ]) ++ [ ./mysql2-mariadb-ssl-mode.patch ];
        };
      };
      nodeGemConfig = rubyGemConfig.mergeGemConfig super.defaultGemConfig nodeMysql2GemConfig;
      nodeRubyGemConfig = rubyGemConfig.mergeGemConfig nodeGemConfig nodeSourceGemConfig;
    in
    {
      vpsadmin-database = super.callPackage ../../packages/api/database.nix { inherit ruby; };
      vpsadmin-api = super.callPackage ../../packages/api/api.nix { inherit ruby; };
      vpsadmin-console-router = super.callPackage ../../packages/console-router { inherit ruby; };
      vpsadmin-download-mounter = super.callPackage ../../packages/download-mounter { inherit ruby; };
      vpsadmin-client = super.callPackage ../../packages/client { inherit ruby; };
      vpsadmin-source = super.callPackage ../../packages/source {
        vpsadminPath = ../../.;
        inherit vpsadminRev;
      };
      vpsadmin-supervisor = super.callPackage ../../packages/api/supervisor.nix { inherit ruby; };
      vpsadmin-webui = super.callPackage ../../packages/webui { };
      libnodectld = super.callPackage ../../packages/libnodectld {
        ruby = self.ruby_vpsadminos;
        gemConfig = nodeRubyGemConfig;
      };
      nodectld = super.callPackage ../../packages/nodectld {
        ruby = self.ruby_vpsadminos;
        gemConfig = nodeRubyGemConfig;
      };
      nodectl = super.callPackage ../../packages/nodectl {
        ruby = self.ruby_vpsadminos;
        gemConfig = nodeRubyGemConfig;
      };
    }
  )
]
