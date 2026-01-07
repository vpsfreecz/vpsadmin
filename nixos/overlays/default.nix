[
  (self: super: {
    vpsadmin-api = super.callPackage ../../packages/api/api.nix { };
    vpsadmin-console-router = super.callPackage ../../packages/console-router { };
    vpsadmin-vnc-router = super.callPackage ../../packages/vnc-router { };
    vpsadmin-download-mounter = super.callPackage ../../packages/download-mounter { };
    vpsadmin-source = super.callPackage ../../packages/source { };
    vpsadmin-supervisor = super.callPackage ../../packages/api/supervisor.nix { };
    vpsadmin-webui = super.callPackage ../../packages/webui { };
    nodectl-v4 = {
      libnodectld = super.callPackage ../../packages/libnodectld { };
      nodectld = super.callPackage ../../packages/nodectld { };
      nodectl = super.callPackage ../../packages/nodectl { };
    };
    nodectl-v5 = {
      libnodectld = super.callPackage ../../packages/libnodectld-v5 { };
      nodectld = super.callPackage ../../packages/nodectld-v5 { };
      nodectl = super.callPackage ../../packages/nodectl-v5 { };
    };
    distconfig = super.callPackage ../../packages/distconfig { };
    vmexec = super.callPackage ../../packages/vmexec { };
    console_server = super.callPackage ../../packages/console_server { };
    console_client = super.callPackage ../../packages/console_client { };
  })
]
