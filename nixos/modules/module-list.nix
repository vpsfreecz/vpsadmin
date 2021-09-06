{
  nixos = [
    ./services/scheduling/cronie.nix
    ./vpsadmin/api.nix
    ./vpsadmin/console-router.nix
    ./vpsadmin/download-mounter.nix
    ./vpsadmin/main.nix
    ./vpsadmin/database.nix
    ./vpsadmin/wait-online.nix
    ./vpsadmin/webui.nix
  ];

  vpsadminos = [
    ./vpsadmin/nodectld.nix
  ];
}
