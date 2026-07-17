{ config, lib, ... }:
{
  _module.args = {
    vpsadminRev = lib.mkDefault null;
    vpsadminRevisionDirty = lib.mkDefault false;
  };
  imports = (import ./module-list.nix).vpsadminos;
}
