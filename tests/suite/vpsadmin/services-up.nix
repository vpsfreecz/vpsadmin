import ../../make-test.nix (
  {
    pkgs,
    ...
  }:
  let
    creds = import ../../configs/nixos/vpsadmin-credentials.nix;
    dbApiUser = creds.database.users.api;
    dbName = creds.database.name;
    redisPassword = creds.redis.password;
  in
  {
    name = "vpsadmin-services-up";

    description = ''
      Boot a NixOS VM with all vpsAdmin services and verify they come up with
      the test configuration.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "services"
    ];

    machines = {
      services = {
        spin = "nixos";
        tags = [ "vpsadmin-services" ];
        networks = [
          { type = "user"; }
          { type = "socket"; }
        ];
        config = {
          imports = [
            ../../configs/nixos/vpsadmin-services.nix
          ];
        };
      };
    };

    testScript = ''
      before(:suite) do
        services.start
      end

      describe 'system' do
        it 'is running' do
          services.wait_until_succeeds('systemctl is-system-running')
        end
      end

      describe 'service' do
        describe 'mariadb' do
          it 'is running' do
            services.wait_for_service('mysql.service')
          end

          it 'is responding' do
            services.wait_until_succeeds("mysql --user=${dbApiUser.user} --password=${dbApiUser.password} -e 'SELECT 1'")
          end

          it 'is set up' do
            services.wait_for_service('vpsadmin-database-setup.service')
          end

          it 'is populated' do
            wait_until_block_succeeds(name: 'mariadb tables populated') do
              _, output = services.succeeds("mysql --user=${dbApiUser.user} --password=${dbApiUser.password} -D ${dbName} -e 'SHOW TABLES'")
              expect(output).to include('users')
              true
            end
          end
        end

        describe 'redis' do
          it 'is running' do
            services.wait_for_service('redis-vpsadmin.service')
          end

          it 'is responding' do
            wait_until_block_succeeds(name: 'redis responds') do
              _, output = services.succeeds("redis-cli -a ${redisPassword} ping")
              expect(output).to include('PONG')
              true
            end
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
            wait_until_block_succeeds(name: 'api responds') do
              _, output = services.succeeds('curl --silent --fail-with-body http://api.vpsadmin.test/')
              expect(output).to include('API description')
              true
            end
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
          it 'is responding through varnish/haproxy' do
            wait_until_block_succeeds(name: 'webui via proxy responds') do
              _, output = services.succeeds('curl --silent --fail-with-body http://webui.vpsadmin.test/')
              expect(output).to include('vpsAdmin')
              true
            end
          end

          it 'is responding directly' do
            wait_until_block_succeeds(name: 'webui direct responds') do
              _, output = services.succeeds('curl --silent --fail-with-body http://127.0.0.1:8134/')
              expect(output).to include('vpsAdmin')
              true
            end
          end
        end

        describe 'mailer node' do
          it 'container is running' do
            wait_until_block_succeeds(name: 'mailer container running') do
              _, output = services.succeeds('nixos-container status mailer', timeout: 180)
              expect(output).to include('up')
              true
            end
          end

          it 'nodectld reports running state' do
            wait_until_block_succeeds(name: 'mailer nodectld running') do
              _, output = services.succeeds('nixos-container run mailer -- nodectl status', timeout: 180)
              expect(output).to include('State: running')
              true
            end
          end
        end
      end
    '';
  }
)
