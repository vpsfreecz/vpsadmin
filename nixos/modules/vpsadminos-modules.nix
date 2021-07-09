{ config, ... }:
{
  imports = (import ./module-list.nix).vpsadminos;
}
