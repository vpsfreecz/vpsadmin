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
      before(:suite) do
        services.start
        breakpoint
      end

      describe 'service' do
        describe 'mariadb' do
          it 'is running' do
            services.wait_for_service('mysql.service')
          end

          it 'is responding' do
            services.wait_until_succeeds("mysql --user=vpsadmin --password=testDatabasePassword -e 'SELECT 1'")
          end

          it 'is set up' do
            services.wait_for_service('vpsadmin-database-setup.service')
          end

          it 'is populated' do
            services.wait_until_succeeds("mysql --user=vpsadmin --password=testDatabasePassword -D vpsadmin -e 'SHOW TABLES' | grep users")
          end
        end

        describe 'redis' do
          it 'is running' do
            services.wait_for_service('redis-vpsadmin.service')
          end

          it 'is responding' do
            services.wait_until_succeeds("redis-cli -a vpsadmin ping | grep PONG")
          end
        end

        example 'nginx is running' do
          services.wait_for_service('nginx.service')
        end

        example 'haproxy is running' do
          services.wait_for_service('haproxy.service')
        end

        example 'varnish is running' do
          services.wait_for_service('varnish.service')
        end

        describe 'rabbitmq' do
          it 'is running' do
            services.wait_for_service('rabbitmq.service')
          end

          it 'is responding' do
            services.wait_until_succeeds("cp /var/lib/rabbitmq/.erlang.cookie /root/")
            services.wait_until_succeeds("rabbitmqctl status")
          end
        end

        describe 'api' do
          it 'is running' do
            services.wait_for_service('vpsadmin-api.service')
          end

          it 'is responding' do
            services.wait_until_succeeds("curl http://api.vpsadmin.test/")
          end
        end

        example 'scheduler is running' do
          services.wait_for_service('vpsadmin-scheduler.service')
        end

        example 'supervisor is running' do
          services.wait_for_service('vpsadmin-supervisor.service')
        end

        example 'console-router is running' do
          services.wait_for_service('vpsadmin-console-router.service')
        end

        describe 'webui' do
          it 'is running' do
            services.wait_for_service('phpfpm-vpsadmin-webui.service')
          end

          it 'is responding' do
            services.wait_until_succeeds("curl http://webui.vpsadmin.test/")
          end
        end
      end
    '';
  }
)
