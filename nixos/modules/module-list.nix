{
  nixos = [
    ./services/scheduling/cronie.nix
    ./vpsadmin/api/default.nix
    ./vpsadmin/api/rake-tasks.nix
    ./vpsadmin/api/scheduler.nix
    ./vpsadmin/console-router.nix
    ./vpsadmin/download-mounter.nix
    ./vpsadmin/frontend.nix
    ./vpsadmin/haproxy.nix
    ./vpsadmin/main.nix
    ./vpsadmin/database.nix
    ./vpsadmin/nodectld/nixos.nix
    ./vpsadmin/rabbitmq.nix
    ./vpsadmin/redis.nix
    ./vpsadmin/supervisor.nix
    ./vpsadmin/wait-online.nix
    ./vpsadmin/webui.nix
  ];

  vpsadminos = [
    ./vpsadmin/main.nix
    ./vpsadmin/nodectld/vpsadminos.nix
  ];
}
