[
  (self: super: {
    vpsadmin-api = super.callPackage ../../packages/api/api.nix { };
    vpsadmin-console-router = super.callPackage ../../packages/console-router { };
    vpsadmin-download-mounter = super.callPackage ../../packages/download-mounter { };
    vpsadmin-source = super.callPackage ../../packages/source { };
    vpsadmin-supervisor = super.callPackage ../../packages/api/supervisor.nix { };
    vpsadmin-webui = super.callPackage ../../packages/webui { };
    libnodectld = super.callPackage ../../packages/libnodectld { };
    nodectld = super.callPackage ../../packages/nodectld { };
    nodectl = super.callPackage ../../packages/nodectl { };
    distconfig = super.callPackage ../../packages/distconfig { };
  })
]
