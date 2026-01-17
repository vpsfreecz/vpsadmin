[
  (
    self: super:
    let
      ruby = super.ruby_3_4;
    in
    {
      vpsadmin-api = super.callPackage ../../packages/api/api.nix { inherit ruby; };
      vpsadmin-console-router = super.callPackage ../../packages/console-router { inherit ruby; };
      vpsadmin-download-mounter = super.callPackage ../../packages/download-mounter { inherit ruby; };
      vpsadmin-source = super.callPackage ../../packages/source { };
      vpsadmin-supervisor = super.callPackage ../../packages/api/supervisor.nix { inherit ruby; };
      vpsadmin-webui = super.callPackage ../../packages/webui { };
      libnodectld = super.callPackage ../../packages/libnodectld { inherit ruby; };
      nodectld = super.callPackage ../../packages/nodectld { inherit ruby; };
      nodectl = super.callPackage ../../packages/nodectl { inherit ruby; };
    }
  )
]
