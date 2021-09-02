{
  nixos = [
    ./services/scheduling/cronie.nix
    ./vpsadmin/api.nix
    ./vpsadmin/database.nix
    ./vpsadmin/webui.nix
  ];

  vpsadminos = [
    ./vpsadmin/nodectld.nix
  ];
}
