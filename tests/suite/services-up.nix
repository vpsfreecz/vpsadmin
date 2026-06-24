import ../make-test.nix (
  {
    pkgs,
    ...
  }:
  let
    creds = import ../configs/nixos/vpsadmin-credentials.nix;
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
            ../configs/nixos/vpsadmin-services.nix
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
            services.wait_until_succeeds("mariadb --user=${dbApiUser.user} --password=${dbApiUser.password} -e 'SELECT 1'")
          end

          it 'is set up' do
            services.wait_for_service('vpsadmin-database-setup.service')
          end

          it 'is populated' do
            wait_until_block_succeeds(name: 'mariadb tables populated') do
              _, output = services.succeeds("mariadb --user=${dbApiUser.user} --password=${dbApiUser.password} -D ${dbName} -e 'SHOW TABLES'")
              expect(output).to include('users')
              true
            end
          end

          it 'has built-in notification templates' do
            wait_until_block_succeeds(name: 'built-in notification templates installed') do
              # notification_template_variants.protocol is a Rails enum:
              # email=0, telegram=1, sms=2.
              _, output = services.succeeds(
                "mariadb --batch --skip-column-names --user=${dbApiUser.user} --password=${dbApiUser.password} -D ${dbName} -e \"" \
                "SELECT COUNT(*) FROM notification_templates nt " \
                "INNER JOIN notification_template_variants ntv ON ntv.notification_template_id = nt.id " \
                "INNER JOIN languages l ON l.id = ntv.language_id " \
                "WHERE nt.name IN ('user_create', 'daily_report', 'expiration_user_active') " \
                "AND l.code = 'en' " \
                "AND ntv.protocol = 0\""
              )
              count = Integer(output.strip)
              expect(count).to eq(3)
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

        describe 'console-router' do
          it 'is running' do
            services.wait_for_service('vpsadmin-console-router.service')
          end

          it 'is responding through nginx/haproxy' do
            wait_until_block_succeeds(name: 'console-router via proxy responds') do
              _, output = services.succeeds(
                'curl --silent --fail-with-body http://console.vpsadmin.test/console.js'
              )
              expect(output).to include('function VpsAdminConsole')
              true
            end
          end

          it 'is responding directly' do
            wait_until_block_succeeds(name: 'console-router direct responds') do
              _, output = services.succeeds(
                'curl --silent --fail-with-body http://127.0.0.1:8000/console.js'
              )
              expect(output).to include('function VpsAdminConsole')
              true
            end
          end
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

          it 'serves public entrypoints and assets directly' do
            [
              '/',
              '/js/haveapi-client.js',
              '/template/css/main.css',
              '/template/icons/info.png',
            ].each do |path|
              wait_until_block_succeeds(name: "webui serves #{path}") do
                _, status = services.succeeds(
                  "curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8134#{path}"
                )
                expect(Integer(status.strip)).to be_between(200, 399)
                true
              end
            end
          end

          it 'does not serve private application files directly' do
            [
              '/lib/functions.lib.php',
              '/pages/page_login.php',
              '/template/template.html',
              '/composer.json',
              '/vendor/autoload.php',
            ].each do |path|
              wait_until_block_succeeds(name: "webui rejects #{path}") do
                _, status = services.succeeds(
                  "curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:8134#{path}"
                )
                expect(status.strip).to eq('404')
                true
              end
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

          it 'mailpit API is responding' do
            services.wait_for_mailpit
            info = services.mailpit_info

            expect(info.fetch('Version')).not_to be_empty
            expect(info.fetch('Messages')).to be >= 0
          end
        end
      end
    '';
  }
)
