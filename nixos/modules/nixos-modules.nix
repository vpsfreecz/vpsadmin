{ config, lib, ... }:
{
  _module.args.vpsadminRev = lib.mkDefault "dev";
  imports = (import ./module-list.nix).nixos;
}
