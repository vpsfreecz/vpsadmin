{
  description = "vpsAdmin (NixOS/vpsAdminOS modules and packages)";

  inputs = {
    vpsadminos.url = "github:vpsfreecz/vpsadminos";
  };

  outputs =
    { self, vpsadminos }:
    let
      overlayList = import ./nixos/overlays/default.nix;
      vpsadminosRubyOverlay = import (vpsadminos.outPath + "/os/overlays/ruby.nix");

      composeExtensions =
        f: g: final: prev:
        let
          fApplied = f final prev;
          gApplied = g final (prev // fApplied);
        in
        fApplied // gApplied;

      composeManyExtensions = overlays: builtins.foldl' composeExtensions (final: prev: { }) overlays;

      composedOverlay = composeManyExtensions ([ vpsadminosRubyOverlay ] ++ overlayList);
    in
    {
      nixosModules = {
        nixos-modules =
          { ... }:
          {
            _module.args.vpsadminos = vpsadminos;
            imports = [ ./nixos/modules/nixos-modules.nix ];
          };
        vpsadminos-modules =
          { ... }:
          {
            _module.args.vpsadminos = vpsadminos;
            imports = [ ./nixos/modules/vpsadminos-modules.nix ];
          };
      };

      overlays = {
        list = overlayList;
        default = composedOverlay;
      };
    };
}
