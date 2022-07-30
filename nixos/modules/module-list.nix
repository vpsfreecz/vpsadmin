{
  nixos = [
    ./services/scheduling/cronie.nix
    ./vpsadmin/api/default.nix
    ./vpsadmin/api/rake-tasks.nix
    ./vpsadmin/api/runners.nix
    ./vpsadmin/api/scheduler.nix
    ./vpsadmin/console-router.nix
    ./vpsadmin/download-mounter.nix
    ./vpsadmin/frontend.nix
    ./vpsadmin/haproxy.nix
    ./vpsadmin/main.nix
    ./vpsadmin/database.nix
    ./vpsadmin/nodectld/nixos.nix
    ./vpsadmin/redis.nix
    ./vpsadmin/wait-online.nix
    ./vpsadmin/webui.nix
  ];

  vpsadminos = [
    ./vpsadmin/nodectld/vpsadminos.nix
  ];
}
