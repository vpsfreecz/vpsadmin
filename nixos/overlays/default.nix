[
  (self: super: {
    libnodectld = super.callPackage ../../packages/libnodectld {};
    nodectld = super.callPackage ../../packages/nodectld {};
    nodectl = super.callPackage ../../packages/nodectl {};
  })
]
