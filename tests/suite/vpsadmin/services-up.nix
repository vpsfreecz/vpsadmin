import ../../make-test.nix (
  {
    pkgs,
    testArgs ? { },
    ...
  }:
  {
    name = "vpsadmin-services-up";

    description = ''
      Boot a NixOS VM with all vpsAdmin services and verify they come up with
      the test configuration.
    '';

    tags = [
      "vpsadmin"
      "services"
    ];

    machines = {
      services = {
        spin = "nixos";
        networks = [
          { type = "user"; }
          { type = "socket"; }
        ];
        config = {
          imports = [
            ../../configs/nixos/vpsadmin-services.nix
          ];

          vpsadmin.test.socketPeers = testArgs.socketPeers or { };
        };
      };
    };

    testScript = ''
      services.start

      services.wait_for_service('mysql.service')
      services.wait_for_service('redis-vpsadmin.service')
      services.wait_for_service('rabbitmq.service')

      services.wait_until_succeeds("mysql --user=vpsadmin --password=vpsadmin -e 'SELECT 1'")

      services.wait_for_service('vpsadmin-api.service')
      services.wait_for_service('vpsadmin-supervisor.service')
      services.wait_for_service('vpsadmin-console-router.service')
      services.wait_for_service('phpfpm-vpsadmin-webui.service')
      services.wait_for_service('nginx.service')
      services.wait_for_service('varnish.service')

      services.wait_until_succeeds("mysql --user=vpsadmin --password=vpsadmin -D vpsadmin -e 'SHOW TABLES' | grep users")
      services.wait_until_succeeds("redis-cli -a vpsadmin ping | grep PONG")

      services.wait_until_succeeds("cp /var/lib/rabbitmq/.erlang.cookie /root/")
      services.wait_until_succeeds("rabbitmqctl status > /dev/null")

      services.wait_until_succeeds("ss -tln | grep ':9292'")
      services.wait_until_succeeds("ss -tln | grep ':8000'")
      services.wait_until_succeeds("ss -tln | grep ':6081'")
      services.wait_until_succeeds("ss -tln | grep ':6379'")
      services.wait_until_succeeds("ss -tln | grep ':5672'")
      services.wait_until_succeeds("ss -tln | grep ':3306'")

      services.wait_until_succeeds("curl --silent --output /dev/null http://api.vpsadmin.test/")
      services.wait_until_succeeds("curl --silent --output /dev/null http://webui.vpsadmin.test/")
      services.wait_until_succeeds("curl --silent --output /dev/null http://127.0.0.1:6081/")
    '';
  }
)
