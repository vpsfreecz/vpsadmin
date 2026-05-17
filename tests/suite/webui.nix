import ../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    location = seed.location;
    clusterSeed = import ../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;

    common = import ./storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };

    playwrightBrowsers = pkgs.playwright-driver.browsers-chromium;
    playwrightNodeModules = pkgs.runCommand "vpsadmin-webui-playwright-node-modules" { } ''
      mkdir -p "$out/lib"
      cp -R ${pkgs.playwright-test}/lib/node_modules "$out/lib/node_modules"
    '';
    playwrightRunner = pkgs.writeShellScriptBin "vpsadmin-webui-playwright" ''
      export NODE_PATH=${playwrightNodeModules}/lib/node_modules''${NODE_PATH:+:$NODE_PATH}
      export PLAYWRIGHT_BROWSERS_PATH="''${PLAYWRIGHT_BROWSERS_PATH:-${playwrightBrowsers}}"
      exec ${pkgs.nodejs}/bin/node ${playwrightNodeModules}/lib/node_modules/@playwright/test/cli.js "$@"
    '';
    playwrightSuite = pkgs.runCommand "vpsadmin-webui-playwright-suite" { } ''
      mkdir -p "$out"
      cp -R ${../playwright/webui}/. "$out/"
    '';
    fixtureScript = pkgs.writeText "vpsadmin-webui-browser-fixtures.rb" ''
      ENV['RACK_ENV'] ||= 'production'
      require 'json'

      Dir.chdir(ENV.fetch('API_DIR'))
      $LOAD_PATH.unshift(File.join(ENV.fetch('API_DIR'), 'lib'))
      require 'vpsadmin'

      fixture_stdout = $stdout.dup
      $stdout.reopen(File::NULL, 'w')

      admin = User.find(${toString adminUser.id})
      User.current = admin
      UserSession.current = UserSession.create!(
        user: admin,
        auth_type: 'basic',
        api_ip_addr: '127.0.0.1',
        client_version: 'webui-playwright'
      )

      def ensure_cluster_resource(row)
        resource = ClusterResource.find_or_initialize_by(name: row[0].to_s)
        resource.label = row[1] if resource.new_record?
        resource.min = row[2] if resource.new_record?
        resource.max = row[3] if resource.new_record?
        resource.stepsize = row[4] if resource.new_record?
        resource.resource_type = row[5] if resource.new_record?
        resource.free_chain = row[6] if resource.new_record? && row[6]
        resource.save! if resource.changed?
        resource
      end

      env = Environment.find(${toString seed.environment.id})
      language = Language.find_by(code: 'en') || Language.first
      user = User.find_or_initialize_by(login: 'webui-user')
      user.assign_attributes(
        full_name: 'Webui Browser User',
        email: 'webui-user@example.test',
        level: 2,
        language: language,
        enable_basic_auth: true,
        enable_token_auth: true,
        enable_oauth2_auth: true,
        mailer_enabled: false,
        password_reset: false,
        lockout: false,
        object_state: :active
      )
      user.set_password('webuiUserPassword')
      user.save!

      quoted_now = ActiveRecord::Base.connection.quote(Time.now)
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO user_accounts (user_id, monthly_payment, paid_until, updated_at)
        VALUES (#{user.id}, 0, NULL, #{quoted_now})
        ON DUPLICATE KEY UPDATE
          monthly_payment = VALUES(monthly_payment),
          paid_until = VALUES(paid_until),
          updated_at = VALUES(updated_at)
      SQL

      EnvironmentUserConfig.find_or_initialize_by(user: user, environment: env).tap do |cfg|
        cfg.can_create_vps = true
        cfg.can_destroy_vps = true
        cfg.vps_lifetime = 0
        cfg.max_vps_count = 10
        cfg.default = true
        cfg.save! if cfg.changed?
      end

      resources = [
        [:cpu, 'CPU', 1, 64, 1, :numeric, nil, 8, 1],
        [:memory, 'Memory', 1024, 131_072, 1, :numeric, nil, 16_384, 1024],
        [:swap, 'Swap', 0, 65_536, 1, :numeric, nil, 4096, 0],
        [:diskspace, 'Disk space', 128, 10_485_760, 1, :numeric, nil, 102_400, 10_240],
        [:ipv4, 'IPv4 address', 0, 64, 1, :object, 'Ip::Free', 4, 0],
        [:ipv4_private, 'Private IPv4 address', 0, 1024, 1, :object, 'Ip::Free', 4, 0],
        [:ipv6, 'IPv6 address', 0, 64, 1, :object, 'Ip::Free', 4, 0]
      ]

      resources.each do |resource_row|
        resource = ensure_cluster_resource(resource_row)

        UserClusterResource.find_or_initialize_by(
          user: user,
          environment: env,
          cluster_resource: resource
        ).tap do |user_resource|
          user_resource.value = resource_row[7]
          user_resource.save! if user_resource.changed?
        end

        DefaultObjectClusterResource.find_or_initialize_by(
          environment: env,
          cluster_resource: resource,
          class_name: 'Vps'
        ).tap do |default_resource|
          default_resource.value = resource_row[8]
          default_resource.save! if default_resource.changed?
        end
      end

      userns = user.user_namespaces.first
      unless userns
        userns = UserNamespace.create!(
          user: user,
          block_count: 1,
          offset: (UserNamespace.maximum(:offset) || 131_072) + 65_536,
          size: 65_536
        )
      end

      userns_map = UserNamespaceMap.find_or_create_by!(
        user_namespace: userns,
        label: 'Webui Browser Map'
      )

      [:uid, :gid].each do |kind|
        UserNamespaceMapEntry.find_or_initialize_by(
          user_namespace_map: userns_map,
          kind: kind,
          vps_id: 0,
          ns_id: 0
        ).tap do |entry|
          entry.count = userns.size
          entry.save! if entry.changed?
        end
      end

      editable_userns_map = UserNamespaceMap
        .where(user_namespace: userns)
        .where('label LIKE ?', 'Webui Editable Browser Map%')
        .first
      editable_userns_map ||= UserNamespaceMap.create!(
        user_namespace: userns,
        label: 'Webui Editable Browser Map'
      )
      if editable_userns_map.label != 'Webui Editable Browser Map'
        editable_userns_map.update!(label: 'Webui Editable Browser Map')
      end

      editable_userns_map.user_namespace_map_entries.delete_all
      editable_userns_uid_entry = UserNamespaceMapEntry.create!(
        user_namespace_map: editable_userns_map,
        kind: :uid,
        vps_id: 0,
        ns_id: 0,
        count: 1
      )
      editable_userns_gid_entry = UserNamespaceMapEntry.create!(
        user_namespace_map: editable_userns_map,
        kind: :gid,
        vps_id: 0,
        ns_id: 0,
        count: 1
      )

      UserNamespaceMap
        .where(user_namespace: userns)
        .where('label LIKE ?', 'Webui Admin Temporary Browser Map%')
        .find_each(&:destroy!)

      public_key = UserPublicKey.find_or_initialize_by(
        user: user,
        label: 'Webui Browser Key'
      )
      public_key.key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFphase2standalone webui-browser@test'
      public_key.auto_add = false
      public_key.save!

      user_data = VpsUserData.find_or_initialize_by(
        user: user,
        label: 'Webui Browser Script'
      )
      user_data.format = 'script'
      user_data.content = "#!/bin/sh\\nprintf 'webui-playwright-user-data\\n' > /root/webui-playwright-user-data.txt\\n"
      user_data.save!

      news_log_message = 'Webui Browser Notice'
      quoted_news_log_message = ActiveRecord::Base.connection.quote(news_log_message)
      quoted_news_log_published_at = ActiveRecord::Base.connection.quote(Time.now - 60)
      ActiveRecord::Base.connection.execute(<<~SQL)
        DELETE FROM news_logs WHERE message = #{quoted_news_log_message}
      SQL
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO news_logs (message, published_at, created_at, updated_at)
        VALUES (#{quoted_news_log_message}, #{quoted_news_log_published_at}, #{quoted_now}, #{quoted_now})
      SQL
      news_log_id = ActiveRecord::Base.connection.select_value(<<~SQL)
        SELECT id FROM news_logs WHERE message = #{quoted_news_log_message} ORDER BY id DESC LIMIT 1
      SQL

      primary_template = OsTemplate.find(1)
      reinstall_template = OsTemplate.find(2)

      fixture_stdout.puts JSON.dump(
        'admin' => {
          'id' => ${toString adminUser.id},
          'username' => ${builtins.toJSON adminUser.login},
          'password' => ${builtins.toJSON adminUser.password}
        },
        'user' => {
          'id' => user.id,
          'username' => user.login,
          'password' => 'webuiUserPassword',
          'publicKey' => {
            'id' => public_key.id,
            'label' => public_key.label
          },
          'userData' => {
            'id' => user_data.id,
            'label' => user_data.label
          },
          'userNamespace' => {
            'id' => userns.id,
            'offset' => userns.offset,
            'blockCount' => userns.block_count,
            'size' => userns.size
          },
          'userNamespaceMap' => {
            'id' => userns_map.id,
            'label' => userns_map.label
          },
          'editableUserNamespaceMap' => {
            'id' => editable_userns_map.id,
            'label' => editable_userns_map.label,
            'entries' => {
              'uid' => {
                'id' => editable_userns_uid_entry.id,
                'vpsId' => editable_userns_uid_entry.vps_id,
                'nsId' => editable_userns_uid_entry.ns_id,
                'count' => editable_userns_uid_entry.count
              },
              'gid' => {
                'id' => editable_userns_gid_entry.id,
                'vpsId' => editable_userns_gid_entry.vps_id,
                'nsId' => editable_userns_gid_entry.ns_id,
                'count' => editable_userns_gid_entry.count
              }
            }
          }
        },
        'location' => {
          'id' => ${toString location.id},
          'label' => ${builtins.toJSON location.label}
        },
        'osTemplates' => {
          'primary' => {
            'id' => primary_template.id,
            'label' => primary_template.label
          },
          'reinstall' => {
            'id' => reinstall_template.id,
            'label' => reinstall_template.label
          }
        },
        'vps' => {
          'resources' => {
            'cpu' => 1,
            'memory' => 1024,
            'swap' => 0,
            'diskspace' => 10_240,
            'ipv4' => 0,
            'ipv4_private' => 0,
            'ipv6' => 0
          }
        },
        'newsLog' => {
          'id' => news_log_id,
          'message' => news_log_message
        }
      )
      fixture_stdout.flush
    '';

    baseMachines = import ../machines/cluster/1-node.nix args;
  in
  {
    name = "vpsadmin-webui";

    description = ''
      Boot a single-node vpsAdmin cluster and exercise user/admin PHP web UI
      flows through Playwright.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "webui"
    ];

    machines = baseMachines // {
      services = baseMachines.services // {
        config = baseMachines.services.config // {
          environment.systemPackages = [
            playwrightRunner
          ];

          system.extraDependencies = [
            fixtureScript
            playwrightBrowsers
            playwrightSuite
          ];
        };
      };
    };

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      WEBUI_FIXTURES = '/tmp/vpsadmin-webui-fixtures.json'

      def wait_for_webui
        wait_until_block_succeeds(name: 'webui responds') do
          _, output = services.succeeds('curl --silent --fail-with-body http://webui.vpsadmin.test/')
          expect(output).to include('vpsAdmin')
          expect(output).not_to include('Unable to connect to the API server')
          true
        end
      end

      def create_webui_browser_fixtures(services)
        _, output = services.succeeds(<<~SH)
          set -euo pipefail

          api_dir="$(systemctl show -p WorkingDirectory --value vpsadmin-api)"
          api_root="$(dirname "$api_dir")"

          API_DIR="$api_dir" "$api_root/ruby-env-wrapped/bin/ruby" ${fixtureScript}
        SH

        JSON.parse(output.to_s.lines.last)
      end

      def write_playwright_fixtures(services, fixtures)
        services.succeeds("cat > #{WEBUI_FIXTURES} <<'JSON'\n#{JSON.pretty_generate(fixtures)}\nJSON\n")
      end

      def run_playwright
        services.succeeds(<<~SH, timeout: 1800)
          set -euo pipefail

          export CI=1
          export HOME=/tmp/vpsadmin-webui-playwright-home
          export PLAYWRIGHT_BROWSERS_PATH=${playwrightBrowsers}
          export WEBUI_BASE_URL=http://webui.vpsadmin.test
          export VPSADMIN_WEBUI_FIXTURES=#{WEBUI_FIXTURES}

          rm -rf "$HOME" /tmp/vpsadmin-webui-playwright-results
          mkdir -p "$HOME"

          cd ${playwrightSuite}
          ${playwrightRunner}/bin/vpsadmin-webui-playwright test \
            --config=${playwrightSuite}/playwright.config.cjs \
            --output=/tmp/vpsadmin-webui-playwright-results
        SH
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_webui
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')

        pool = create_pool(
          services,
          node_id: node1_id,
          label: 'webui-browser-vps',
          filesystem: primary_pool_fs,
          role: 'hypervisor'
        )
        wait_for_pool_online(services, pool.fetch('id'))

        write_playwright_fixtures(
          services,
          create_webui_browser_fixtures(services)
        )
      end

      describe 'webui browser flow' do
        it 'passes Playwright user and admin tests' do
          run_playwright
        end
      end
    '';
  }
)
