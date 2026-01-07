{
  nixos = [
    ./services/scheduling/cronie.nix
    ./vpsadmin/api/default.nix
    ./vpsadmin/api/rake-tasks.nix
    ./vpsadmin/api/scheduler.nix
    ./vpsadmin/database-setup.nix
    ./vpsadmin/console-router.nix
    ./vpsadmin/vnc-router.nix
    ./vpsadmin/download-mounter.nix
    ./vpsadmin/frontend.nix
    ./vpsadmin/varnish.nix
    ./vpsadmin/haproxy.nix
    ./vpsadmin/main.nix
    ./vpsadmin/nixos.nix
    ./vpsadmin/database.nix
    ./vpsadmin/nodectld/nixos.nix
    ./vpsadmin/rabbitmq.nix
    ./vpsadmin/redis.nix
    ./vpsadmin/supervisor.nix
    ./vpsadmin/wait-online.nix
    ./vpsadmin/webui.nix
  ];

  vpsadminos = [
    ./vpsadmin/console-server.nix
    ./vpsadmin/main.nix
    ./vpsadmin/nodectld/vpsadminos.nix
  ];
}
