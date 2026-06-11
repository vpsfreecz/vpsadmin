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
      nodeRubyGemConfig = rubyGemConfig.mergeGemConfig super.defaultGemConfig nodeSourceGemConfig;
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
