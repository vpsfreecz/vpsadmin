{
  nixos = [
    ./vpsadmin/database.nix
    ./vpsadmin/webui.nix
  ];

  vpsadminos = [
    ./vpsadmin/nodectld.nix
  ];
}
