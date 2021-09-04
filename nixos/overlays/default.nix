[
  (self: super: {
    vpsadmin-api = super.callPackage ../../packages/api {};
    vpsadmin-console-router = super.callPackage ../../packages/console-router {};
    libnodectld = super.callPackage ../../packages/libnodectld {};
    nodectld = super.callPackage ../../packages/nodectld {};
    nodectl = super.callPackage ../../packages/nodectl {};
  })
]
