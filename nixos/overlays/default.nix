[
  (
    self: super:
    let
      ruby = super.ruby_3_4;
    in
    {
      vpsadmin-database = super.callPackage ../../packages/api/database.nix { inherit ruby; };
      vpsadmin-api = super.callPackage ../../packages/api/api.nix { inherit ruby; };
      vpsadmin-console-router = super.callPackage ../../packages/console-router { inherit ruby; };
      vpsadmin-vnc-router = super.callPackage ../../packages/vnc-router { };
      vpsadmin-download-mounter = super.callPackage ../../packages/download-mounter { inherit ruby; };
      vpsadmin-client = super.callPackage ../../packages/client { inherit ruby; };
      vpsadmin-source = super.callPackage ../../packages/source { };
      vpsadmin-supervisor = super.callPackage ../../packages/api/supervisor.nix { inherit ruby; };
      vpsadmin-webui = super.callPackage ../../packages/webui { };
      nodectl-v4 = {
        libnodectld = super.callPackage ../../packages/libnodectld { ruby = self.ruby_vpsadminos; };
        nodectld = super.callPackage ../../packages/nodectld { ruby = self.ruby_vpsadminos; };
        nodectl = super.callPackage ../../packages/nodectl { ruby = self.ruby_vpsadminos; };
      };
      nodectl-v5 = {
        libnodectld = super.callPackage ../../packages/libnodectld-v5 { inherit ruby; };
        nodectld = super.callPackage ../../packages/nodectld-v5 { inherit ruby; };
        nodectl = super.callPackage ../../packages/nodectl-v5 { inherit ruby; };
      };
      distconfig = super.callPackage ../../packages/distconfig { inherit ruby; };
      vmexec = super.callPackage ../../packages/vmexec { inherit ruby; };
      console_server = super.callPackage ../../packages/console_server { inherit ruby; };
      console_client = super.callPackage ../../packages/console_client { inherit ruby; };
    }
  )
]
