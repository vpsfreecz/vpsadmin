{ config, ... }:
{
  imports = (import ./module-list.nix).nixos;
}
