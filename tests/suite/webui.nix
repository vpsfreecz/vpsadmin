import ../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    location = seed.location;
    clusterSeed = import ../../api/db/seeds/test-2-node.nix;
    node1Seed = clusterSeed.nodes.node1;
    node2Seed = clusterSeed.nodes.node2;

    common = import ./storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = node1Seed.id;
      node2Id = node2Seed.id;
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
    webuiTestScriptCommon = common + ''
      require 'shellwords'

      configure_examples do |config|
        config.default_order = :defined
      end

      WEBUI_FIXTURES = '/tmp/vpsadmin-webui-fixtures.json' unless defined?(WEBUI_FIXTURES)

      def start_webui_machine(machine)
        machine.start unless machine.running?
      end

      def wait_for_webui
        wait_until_block_succeeds(name: 'webui responds') do
          _, output = services.succeeds('curl --silent --fail-with-body http://webui.vpsadmin.test/')
          expect(output).to include('vpsAdmin')
          expect(output).not_to include('Unable to connect to the API server')
          true
        end
      end

      WEBUI_NODE1_SECONDARY_POOL_FS = 'tank/webui-node1-secondary' unless defined?(WEBUI_NODE1_SECONDARY_POOL_FS)
      WEBUI_NODE2_POOL_FS = 'tank/webui-node2' unless defined?(WEBUI_NODE2_POOL_FS)
      WEBUI_SECONDARY_LOCATION_LABEL = 'webui-browser-location-b' unless defined?(WEBUI_SECONDARY_LOCATION_LABEL)
      WEBUI_ADMIN_OPS_ENV_LABEL = 'webui-browser-env-b' unless defined?(WEBUI_ADMIN_OPS_ENV_LABEL)
      WEBUI_ADMIN_OPS_LOCATION_LABEL = 'webui-browser-admin-location-b' unless defined?(WEBUI_ADMIN_OPS_LOCATION_LABEL)

      def webui_pool_id(filesystem = primary_pool_fs)
        row = services.mariadb_json_rows(sql: <<~SQL).first
          SELECT JSON_OBJECT('id', id)
          FROM pools
          WHERE filesystem = #{filesystem.inspect}
          LIMIT 1
        SQL

        row && row.fetch('id')
      end

      def ensure_webui_pool(
        node_id: node1_id,
        label: 'webui-browser-vps',
        filesystem: primary_pool_fs,
        role: 'hypervisor'
      )
        pool_id = webui_pool_id(filesystem)

        unless pool_id
          pool = create_pool(
            services,
            node_id: node_id,
            label: label,
            filesystem: filesystem,
            role: role
          )
          pool_id = pool.fetch('id')
        end

        wait_for_pool_online(services, pool_id)
        pool_id
      end

      def ensure_webui_default_pool
        ensure_webui_pool
      end

      def prepare_webui_node2
        start_webui_machine(node2)
        wait_for_running_nodectld(node2)
        wait_for_webui_node_ready(node2, node2_id)
        prepare_node_queues(node2)
      end

      def ensure_webui_migration_pools
        prepare_webui_node2
        node1_primary = ensure_webui_default_pool
        node1_secondary = ensure_webui_pool(
          node_id: node1_id,
          label: 'webui-browser-node1-secondary',
          filesystem: WEBUI_NODE1_SECONDARY_POOL_FS
        )
        node2_primary = ensure_webui_pool(
          node_id: node2_id,
          label: 'webui-browser-node2',
          filesystem: WEBUI_NODE2_POOL_FS
        )

        {
          'node1Primary' => node1_primary,
          'node1Secondary' => node1_secondary,
          'node2Primary' => node2_primary
        }
      end

      def prepare_webui_migration_keys
        pools = ensure_webui_migration_pools
        generate_migration_keys(services)
        pools
      end

      def move_webui_node2_to_secondary_location
        services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          env = Environment.find(${toString seed.environment.id})
          location = Location.find_or_initialize_by(
            label: '#{WEBUI_SECONDARY_LOCATION_LABEL}'
          )
          location.assign_attributes(
            environment: env,
            domain: 'lab',
            description: 'Webui browser secondary location',
            remote_console_server: 'http://console.vpsadmin.test',
            has_ipv6: false
          )
          location.save! if location.changed?

          node = Node.find(#{node2_id})
          node.update!(location: location) if node.location_id != location.id

          puts JSON.dump(location_id: location.id, node_id: node.id)
        RUBY
      end

      def move_webui_node2_to_admin_ops_location
        services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          env = Environment.find_or_initialize_by(
            label: '#{WEBUI_ADMIN_OPS_ENV_LABEL}'
          )
          env.assign_attributes(
            domain: 'admin-ops.vpsadmin.test',
            description: 'Webui browser admin operation environment',
            can_create_vps: true,
            can_destroy_vps: true,
            vps_lifetime: 0,
            max_vps_count: 120,
            user_ip_ownership: false
          )
          env.save! if env.changed? || env.new_record?

          location = Location.find_or_initialize_by(
            label: '#{WEBUI_ADMIN_OPS_LOCATION_LABEL}'
          )
          location.assign_attributes(
            environment: env,
            domain: 'lab-admin-b',
            description: 'Webui browser admin operation location',
            remote_console_server: 'http://console.vpsadmin.test',
            has_ipv6: false
          )
          location.save! if location.changed? || location.new_record?

          node = Node.find(#{node2_id})
          node.update!(location: location) if node.location_id != location.id

          puts JSON.dump(
            environment_id: env.id,
            location_id: location.id,
            node_id: node.id
          )
        RUBY
      end

      def prepare_webui_cross_location_swap
        prepare_webui_node2
        prepare_node_queues(node1)
        secondary_location = move_webui_node2_to_secondary_location
        node1_primary = ensure_webui_default_pool
        node2_primary = ensure_webui_pool(
          node_id: node2_id,
          label: 'webui-browser-node2',
          filesystem: WEBUI_NODE2_POOL_FS
        )

        node1_key = generate_pool_migration_key(
          node1,
          pool_name: primary_pool_fs.split('/').first
        )
        node2_key = generate_pool_migration_key(
          node2,
          pool_name: WEBUI_NODE2_POOL_FS.split('/').first
        )

        set_pool_migration_public_key(
          services,
          admin_user_id: admin_user_id,
          pool_id: node1_primary,
          public_key: node1_key
        )
        set_pool_migration_public_key(
          services,
          admin_user_id: admin_user_id,
          pool_id: node2_primary,
          public_key: node2_key
        )

        {
          'node1Primary' => node1_primary,
          'node2Primary' => node2_primary,
          'secondaryLocation' => secondary_location
        }
      end

      def prepare_webui_admin_ops_cluster
        prepare_webui_node2
        prepare_node_queues(node1)
        secondary_location = move_webui_node2_to_admin_ops_location
        node1_primary = ensure_webui_default_pool
        node2_primary = ensure_webui_pool(
          node_id: node2_id,
          label: 'webui-browser-node2',
          filesystem: WEBUI_NODE2_POOL_FS
        )
        generate_migration_keys(services)

        {
          'node1Primary' => node1_primary,
          'node2Primary' => node2_primary,
          'secondaryLocation' => secondary_location
        }
      end

      def unlock_webui_transaction_signing_key
        services.unlock_transaction_signing_key(passphrase: 'test')
      rescue OsVm::CommandFailed => e
        raise unless e.message.include?('already unlocked')
      end

      def create_webui_browser_fixtures(services)
        _, output = services.succeeds(<<~SH)
          set -euo pipefail

          api_dir="$(systemctl show -p WorkingDirectory --value vpsadmin-api)"
          api_root="$(dirname "$api_dir")"

          API_DIR="$api_dir" "$api_root/ruby-env-wrapped/bin/ruby" ${fixtureScript} > #{WEBUI_FIXTURES}
          cat #{WEBUI_FIXTURES}
        SH

        JSON.parse(output.to_s.lines.last)
      end

      def refresh_webui_node_status(node)
        wait_until_block_succeeds(name: "refresh #{node.name} runtime status", timeout: 300) do
          node.succeeds('nodectl refresh', timeout: 180)
          true
        end
      end

      def wait_for_webui_node_ready(node, node_id)
        last_node = nil

        refresh_webui_node_status(node)

        wait_until_block_succeeds(name: "node #{node_id} ready in API", timeout: 1200) do
          _, output = services.vpsadminctl.succeeds(args: ['node', 'show', node_id.to_s])
          last_node = output.fetch('node')

          last_node.fetch('status') == true && last_node.fetch('pool_status') == true
        end
      rescue OsVm::TimeoutError
        raise "Timed out waiting for node #{node_id} ready in API: #{last_node.inspect}"
      end

      def prepare_webui_playwright
        [services, node1].each { |machine| start_webui_machine(machine) }
        services.wait_for_vpsadmin_api
        wait_for_webui
        wait_for_running_nodectld(node1)
        wait_for_webui_node_ready(node1, node1_id)
        unlock_webui_transaction_signing_key
        ensure_webui_default_pool
        prepare_webui_component

        create_webui_browser_fixtures(services)
      end

      def prepare_webui_component; end

      def webui_pending_transaction_chains
        queued = services.class::CHAIN_STATES.fetch(:queued)
        rollbacking = services.class::CHAIN_STATES.fetch(:rollbacking)

        services.mariadb_json_rows(sql: <<~SQL)
          SELECT JSON_OBJECT(
            'id', id,
            'name', name,
            'state', state,
            'progress', progress,
            'size', size
          )
          FROM transaction_chains
          WHERE state IN (#{queued}, #{rollbacking})
            AND (name IS NULL OR name NOT LIKE 'webui_tx_%')
          ORDER BY id
          LIMIT 25
        SQL
      end

      def wait_for_webui_transaction_chains_idle(timeout: 900)
        pending = []
        deadline = Time.now + timeout

        loop do
          pending = webui_pending_transaction_chains
          return true if pending.empty?

          raise OsVm::TimeoutError if Time.now >= deadline

          sleep 1
        end
      rescue OsVm::TimeoutError
        raise "Timed out waiting for webui transaction chains to become idle: #{pending.inspect}"
      end

      def run_playwright(script_name, *specs)
        raise ArgumentError, 'at least one Playwright spec is required' if specs.empty?

        safe_name = script_name.gsub(/[^A-Za-z0-9_.-]/, '-')
        spec_args = specs.map { |spec| Shellwords.escape(spec) }.join(' ')

        wait_for_webui_transaction_chains_idle

        playwright_failed = false

        begin
          services.succeeds(<<~SH, timeout: 1800)
            set -euo pipefail

            export CI=1
            export HOME=/tmp/vpsadmin-webui-playwright-home-#{safe_name}
            export PLAYWRIGHT_BROWSERS_PATH=${playwrightBrowsers}
            export WEBUI_BASE_URL=http://webui.vpsadmin.test
            export VPSADMIN_WEBUI_FIXTURES=#{WEBUI_FIXTURES}

            rm -rf "$HOME" /tmp/vpsadmin-webui-playwright-results-#{safe_name}
            mkdir -p "$HOME"

            cd ${playwrightSuite}
            ${playwrightRunner}/bin/vpsadmin-webui-playwright test #{spec_args} \
              --config=${playwrightSuite}/playwright.config.cjs \
              --output=/tmp/vpsadmin-webui-playwright-results-#{safe_name}
          SH
        rescue StandardError
          playwright_failed = true
          raise
        ensure
          begin
            wait_for_webui_transaction_chains_idle
          rescue StandardError => e
            raise unless playwright_failed

            warn "Unable to wait for webui transaction chains after #{script_name} failed: #{e.message}"
          end
        end
      end

      before(:suite) do
        prepare_webui_playwright
      end
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

      def ensure_dataset_in_pool(user, pool, name)
        dataset = Dataset.find_or_initialize_by(name: name, user: user)
        dataset.assign_attributes(
          user: user,
          user_editable: true,
          user_create: true,
          user_destroy: true,
          object_state: :active,
          confirmed: :confirmed
        )
        dataset.save! if dataset.changed? || dataset.new_record?

        DatasetInPool.find_or_initialize_by(dataset: dataset, pool: pool).tap do |dip|
          dip.confirmed = :confirmed
          dip.save! if dip.changed? || dip.new_record?
        end
      end

      def ensure_pool_dataset_properties(pool)
        VpsAdmin::API::DatasetProperties::Registrator.properties.each do |name, prop|
          DatasetProperty.find_or_create_by!(
            pool: pool,
            dataset_in_pool_id: nil,
            dataset_id: nil,
            name: name.to_s
          ) do |p|
            p.value = prop.meta[:default]
            p.inherited = false
            p.confirmed = DatasetProperty.confirmed(:confirmed)
          end
        end
      end

      def ensure_webui_user(login:, full_name:, email:, password:, env:, language:)
        user = User.find_or_initialize_by(login: login)
        user.assign_attributes(
          full_name: full_name,
          email: email,
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
        user.set_password(password)
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
          cfg.max_vps_count = 120
          cfg.default = true
          cfg.save! if cfg.changed?
        end

        user
      end

      env = Environment.find(${toString seed.environment.id})
      language = Language.find_by(code: 'en') || Language.first
      ensure_vps_lifetime = lambda do |target_env, state, reason|
        DefaultLifetimeValue.find_or_initialize_by(
          environment: target_env,
          class_name: 'Vps',
          direction: DefaultLifetimeValue.directions[:enter],
          state: DefaultLifetimeValue.states[state]
        ).tap do |lifetime|
          lifetime.add_expiration = 7 * 24 * 60 * 60
          lifetime.reason = reason
          lifetime.save! if lifetime.changed? || lifetime.new_record?
        end
      end
      ensure_vps_lifetime.call(env, :soft_delete, 'Webui browser VPS delete')
      ensure_vps_lifetime.call(env, :hard_delete, 'Webui browser VPS hard delete')

      user = ensure_webui_user(
        login: 'webui-user',
        full_name: 'Webui Browser User',
        email: 'webui-user@example.test',
        password: 'webuiUserPassword',
        env: env,
        language: language
      )
      secondary_user = ensure_webui_user(
        login: 'webui-user-secondary',
        full_name: 'Webui Browser Secondary User',
        email: 'webui-user-secondary@example.test',
        password: 'webuiSecondaryPassword',
        env: env,
        language: language
      )

      quoted_now = ActiveRecord::Base.connection.quote(Time.now)

      resources = [
        [:cpu, 'CPU', 1, 64, 1, :numeric, nil, 64, 1],
        [:memory, 'Memory', 1024, 131_072, 1, :numeric, nil, 131_072, 1024],
        [:swap, 'Swap', 0, 65_536, 1, :numeric, nil, 65_536, 0],
        [:diskspace, 'Disk space', 128, 10_485_760, 1, :numeric, nil, 1_048_576, 10_240],
        [:ipv4, 'IPv4 address', 0, 64, 1, :object, 'Ip::Free', 64, 0],
        [:ipv4_private, 'Private IPv4 address', 0, 1024, 1, :object, 'Ip::Free', 64, 0],
        [:ipv6, 'IPv6 address', 0, 64, 1, :object, 'Ip::Free', 64, 0]
      ]

      resources.each do |resource_row|
        resource = ensure_cluster_resource(resource_row)

        [user, secondary_user].each do |resource_user|
          UserClusterResource.find_or_initialize_by(
            user: resource_user,
            environment: env,
            cluster_resource: resource
          ).tap do |user_resource|
            user_resource.value = resource_row[7]
            user_resource.save! if user_resource.changed?
          end
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

      node2_env = Node.find(${toString node2Seed.id}).location.environment
      if node2_env.id != env.id
        ensure_vps_lifetime.call(node2_env, :soft_delete, 'Webui browser VPS delete')
        ensure_vps_lifetime.call(
          node2_env,
          :hard_delete,
          'Webui browser VPS hard delete'
        )

        [user, secondary_user].each do |resource_user|
          EnvironmentUserConfig.find_or_initialize_by(
            user: resource_user,
            environment: node2_env
          ).tap do |cfg|
            cfg.can_create_vps = true
            cfg.can_destroy_vps = true
            cfg.vps_lifetime = 0
            cfg.max_vps_count = 120
            cfg.default = true
            cfg.save! if cfg.changed? || cfg.new_record?
          end
        end

        resources.each do |resource_row|
          resource = ensure_cluster_resource(resource_row)

          [user, secondary_user].each do |resource_user|
            UserClusterResource.find_or_initialize_by(
              user: resource_user,
              environment: node2_env,
              cluster_resource: resource
            ).tap do |user_resource|
              user_resource.value = resource_row[7]
              user_resource.save! if user_resource.changed? || user_resource.new_record?
            end
          end

          DefaultObjectClusterResource.find_or_initialize_by(
            environment: node2_env,
            cluster_resource: resource,
            class_name: 'Vps'
          ).tap do |default_resource|
            default_resource.value = resource_row[8]
            default_resource.save! if default_resource.changed? || default_resource.new_record?
          end
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

      alternate_userns_map = UserNamespaceMap.find_or_create_by!(
        user_namespace: userns,
        label: 'Webui VPS Alternate Browser Map'
      )
      alternate_userns_map.user_namespace_map_entries.delete_all
      [:uid, :gid].each do |kind|
        UserNamespaceMapEntry.create!(
          user_namespace_map: alternate_userns_map,
          kind: kind,
          vps_id: 0,
          ns_id: 0,
          count: userns.size
        )
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

      secondary_userns = secondary_user.user_namespaces.first
      unless secondary_userns
        secondary_userns = UserNamespace.create!(
          user: secondary_user,
          block_count: 1,
          offset: (UserNamespace.maximum(:offset) || 131_072) + 65_536,
          size: 65_536
        )
      end

      secondary_userns_map = UserNamespaceMap.find_or_create_by!(
        user_namespace: secondary_userns,
        label: 'Webui Secondary Browser Map'
      )

      [:uid, :gid].each do |kind|
        UserNamespaceMapEntry.find_or_initialize_by(
          user_namespace_map: secondary_userns_map,
          kind: kind,
          vps_id: 0,
          ns_id: 0
        ).tap do |entry|
          entry.count = secondary_userns.size
          entry.save! if entry.changed? || entry.new_record?
        end
      end

      public_key = UserPublicKey.find_or_initialize_by(
        user: user,
        label: 'Webui Browser Key'
      )
      public_key.key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFphase2standalone webui-browser@test'
      public_key.auto_add = false
      public_key.save!

      extra_public_keys = [
        ['Webui Browser Key Auto', 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwebuiautokey webui-browser-auto@test', true],
        ['Webui Browser Key Spare', 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwebuisparekey webui-browser-spare@test', false]
      ].map do |label, key, auto_add|
        UserPublicKey.find_or_initialize_by(
          user: user,
          label: label
        ).tap do |pubkey|
          pubkey.key = key
          pubkey.auto_add = auto_add
          pubkey.save!
        end
      end

      secondary_public_key = UserPublicKey.find_or_initialize_by(
        user: secondary_user,
        label: 'Webui Secondary Browser Key'
      )
      secondary_public_key.key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwebuisecondary webui-secondary@test'
      secondary_public_key.auto_add = false
      secondary_public_key.save!

      user_data = VpsUserData.find_or_initialize_by(
        user: user,
        label: 'Webui Browser Script'
      )
      user_data.format = 'script'
      user_data.content = "#!/bin/sh\\nprintf 'webui-playwright-user-data\\n' > /root/webui-playwright-user-data.txt\\n"
      user_data.save!

      extra_user_data = [
        ['Webui Browser Cloud Config', 'cloudinit_config', "#cloud-config\\nwrite_files:\\n  - path: /root/webui-cloud-config.txt\\n    content: webui-cloud-config\\n"],
        ['Webui Browser Vendor Data', 'script', "#!/bin/sh\\nprintf 'webui-vendor-data\\n' > /root/webui-vendor-data.txt\\n"]
      ].map do |label, format, content|
        VpsUserData.find_or_initialize_by(
          user: user,
          label: label
        ).tap do |data|
          data.format = format
          data.content = content
          data.save!
        end
      end

      secondary_user_data = VpsUserData.find_or_initialize_by(
        user: secondary_user,
        label: 'Webui Secondary Browser Script'
      )
      secondary_user_data.format = 'script'
      secondary_user_data.content = "#!/bin/sh\\nprintf 'webui-secondary-user-data\\n' > /root/webui-secondary-user-data.txt\\n"
      secondary_user_data.save!

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

      node = Node.find(${toString node1Seed.id})
      node2 = Node.find(${toString node2Seed.id})

      readonly_session = UserSession.create!(
        user: user,
        user_agent: UserAgent.find_or_create!('webui-playwright-readonly'),
        auth_type: 'basic',
        api_ip_addr: '127.0.0.1',
        client_version: 'webui-playwright-readonly',
        label: 'Webui Browser Readonly Fixture'
      )

      history_message = 'Webui Browser History Event'
      ObjectHistory
        .where(
          tracked_object_type: 'User',
          tracked_object_id: user.id,
          event_type: 'webui_readonly'
        )
        .delete_all
      history = ObjectHistory.create!(
        tracked_object: user,
        user: user,
        user_session: readonly_session,
        event_type: 'webui_readonly',
        event_data: { 'message' => history_message },
        created_at: Time.now - 30
      )

      readonly_chain_ids = ActiveRecord::Base.connection.select_values(<<~SQL)
        SELECT id FROM transaction_chains WHERE name = 'webui_readonly'
      SQL
      if readonly_chain_ids.any?
        ActiveRecord::Base.connection.execute(<<~SQL)
          DELETE FROM transactions
          WHERE transaction_chain_id IN (#{readonly_chain_ids.join(',')})
        SQL
        ActiveRecord::Base.connection.execute(<<~SQL)
          DELETE FROM transaction_chain_concerns
          WHERE transaction_chain_id IN (#{readonly_chain_ids.join(',')})
        SQL
        ActiveRecord::Base.connection.execute(<<~SQL)
          DELETE FROM transaction_chains
          WHERE id IN (#{readonly_chain_ids.join(',')})
        SQL
      end

      readonly_chain_time = ActiveRecord::Base.connection.quote(Time.now - 20)
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO transaction_chains
          (name, type, state, size, progress, user_id, user_session_id,
           urgent_rollback, concern_type, created_at, updated_at)
        VALUES
          ('webui_readonly', 'TransactionChains::User::NewLogin', 2, 1, 1,
           #{user.id}, #{readonly_session.id}, 0, 0,
           #{readonly_chain_time}, #{readonly_chain_time})
      SQL
      readonly_chain_id = ActiveRecord::Base.connection.select_value('SELECT LAST_INSERT_ID()')
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO transaction_chain_concerns
          (transaction_chain_id, class_name, row_id)
        VALUES
          (#{readonly_chain_id}, 'User', #{user.id})
      SQL
      readonly_tx_input = ActiveRecord::Base.connection.quote({
        transaction_chain: readonly_chain_id.to_i,
        depends_on: nil,
        handle: 10_001,
        node: node.id,
        reversible: 0,
        input: { sleep: nil }
      }.to_json)
      readonly_tx_output = ActiveRecord::Base.connection.quote({ ok: true }.to_json)
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO transactions
          (user_id, node_id, handle, depends_on_id, urgent, priority, status,
           done, input, output, transaction_chain_id, reversible, queue,
           created_at, started_at, finished_at)
        VALUES
          (#{user.id}, #{node.id}, 10001, NULL, 0, 0, 1,
           1, #{readonly_tx_input}, #{readonly_tx_output}, #{readonly_chain_id},
           0, 'general', #{readonly_chain_time}, #{readonly_chain_time},
           #{readonly_chain_time})
      SQL
      readonly_transaction_id = ActiveRecord::Base.connection.select_value('SELECT LAST_INSERT_ID()')

      webui_transaction_names = %w[
        webui_tx_queued
        webui_tx_done
        webui_tx_rollbacking
        webui_tx_failed
      ]
      webui_transaction_chain_ids = TransactionChain
        .where(name: webui_transaction_names)
        .pluck(:id)
      if webui_transaction_chain_ids.any?
        ids = webui_transaction_chain_ids.join(',')
        ActiveRecord::Base.connection.execute("DELETE FROM transactions WHERE transaction_chain_id IN (#{ids})")
        ActiveRecord::Base.connection.execute("DELETE FROM transaction_chain_concerns WHERE transaction_chain_id IN (#{ids})")
        ActiveRecord::Base.connection.execute("DELETE FROM transaction_chains WHERE id IN (#{ids})")
      end

      def create_webui_transaction_fixture(name:, state:, progress:, status:, done:, user:, session:, node:, concern_class:, concern_id:, transaction: true)
        created_at = Time.now - 10
        chain = TransactionChain.create!(
          name: name,
          type: TransactionChains::User::NewLogin.name,
          state: state,
          size: 1,
          progress: progress,
          user: user,
          user_session: session,
          concern_type: :chain_affect,
          urgent_rollback: false,
          created_at: created_at,
          updated_at: created_at
        )

        TransactionChainConcern.create!(
          transaction_chain: chain,
          class_name: concern_class,
          row_id: concern_id
        )

        tx = nil
        if transaction
          prev_user = User.current
          begin
            User.current = user
            tx = Transaction.create!(
              transaction_chain: chain,
              user: user,
              node: node,
              handle: Transactions::Utils::NoOp.t_type,
              queue: 'general',
              urgent: false,
              priority: 0
            )
          ensure
            User.current = prev_user
          end
          transaction_time = done == :done ? created_at : nil
          tx.update_columns(
            status: status,
            done: Transaction.dones.fetch(done),
            input: {
              transaction_chain: chain.id,
              depends_on: nil,
              handle: tx.handle,
              node: node.id,
              reversible: Transaction.reversibles.fetch(:is_reversible),
              input: {
                fixture: name
              }
            }.to_json,
            output: {
              fixture: name,
              status: status == 1 ? 'ok' : 'failed'
            }.to_json,
            created_at: created_at,
            started_at: transaction_time,
            finished_at: transaction_time
          )
        end

        {
          'id' => chain.id,
          'name' => chain.name,
          'label' => chain.label,
          'state' => chain.state,
          'progress' => chain.progress,
          'transactionId' => tx&.id,
          'transactionName' => tx&.name,
          'transactionType' => tx&.handle,
          'transactionDone' => tx&.done,
          'transactionSuccess' => tx&.status,
          'fixture' => name
        }
      end

      webui_transactions = {
        'queued' => create_webui_transaction_fixture(
          name: 'webui_tx_queued',
          state: :queued,
          progress: 0,
          status: 0,
          done: :waiting,
          user: user,
          session: readonly_session,
          node: node,
          concern_class: 'User',
          concern_id: user.id,
          transaction: false
        ),
        'done' => create_webui_transaction_fixture(
          name: 'webui_tx_done',
          state: :done,
          progress: 1,
          status: 1,
          done: :done,
          user: user,
          session: readonly_session,
          node: node,
          concern_class: 'User',
          concern_id: user.id
        ),
        'rollbacking' => create_webui_transaction_fixture(
          name: 'webui_tx_rollbacking',
          state: :rollbacking,
          progress: 0,
          status: 0,
          done: :waiting,
          user: user,
          session: readonly_session,
          node: node,
          concern_class: 'User',
          concern_id: user.id
        ),
        'failed' => create_webui_transaction_fixture(
          name: 'webui_tx_failed',
          state: :failed,
          progress: 1,
          status: 0,
          done: :done,
          user: user,
          session: readonly_session,
          node: node,
          concern_class: 'User',
          concern_id: user.id
        )
      }

      primary_template = OsTemplate.find(1)
      reinstall_template = OsTemplate.find(2)
      webui_pool = Pool.where(node: node, role: Pool.roles[:hypervisor]).order(:id).first
      raise 'webui hypervisor pool not found' unless webui_pool
      Pool.where(role: Pool.roles[:hypervisor]).find_each do |pool|
        ensure_pool_dataset_properties(pool)
      end

      jumpto_network = Network.find_or_initialize_by(
        address: '203.0.113.128',
        prefix: 29
      )
      jumpto_network.assign_attributes(
        ip_version: 4,
        label: 'Webui Jumpto Network',
        managed: false,
        primary_location: Location.find(${toString location.id}),
        role: :public_access,
        purpose: :export,
        split_access: :no_access,
        split_prefix: 32
      )
      jumpto_network.save! if jumpto_network.changed? || jumpto_network.new_record?

      LocationNetwork.find_or_initialize_by(
        location: Location.find(${toString location.id}),
        network: jumpto_network
      ).tap do |locnet|
        locnet.primary = true
        locnet.priority = 10
        locnet.autopick = true
        locnet.userpick = true
        locnet.save! if locnet.changed? || locnet.new_record?
      end

      jumpto_export_dip = ensure_dataset_in_pool(
        user,
        webui_pool,
        'webui-jumpto-export-dataset'
      )

      jumpto_export = Export.find_or_initialize_by(
        dataset_in_pool: jumpto_export_dip,
        snapshot_in_pool_clone_n: 0
      )
      export_attrs = {
        snapshot_in_pool_clone: nil,
        user: user,
        all_vps: false,
        path: "/export/#{jumpto_export_dip.dataset.full_name}",
        rw: true,
        sync: true,
        subtree_check: false,
        root_squash: false,
        threads: 8,
        enabled: true,
        object_state: :active,
        confirmed: :confirmed
      }
      if jumpto_export.new_record?
        Uuid.generate_for_new_record! do |uuid|
          jumpto_export.assign_attributes(export_attrs)
          jumpto_export.uuid = uuid
          jumpto_export.save!
          jumpto_export
        end
      else
        jumpto_export.assign_attributes(export_attrs)
        jumpto_export.uuid ||= Uuid.generate!
        jumpto_export.save! if jumpto_export.changed?
      end

      jumpto_export_netif = NetworkInterface.find_or_initialize_by(
        export: jumpto_export,
        name: 'eth0'
      )
      jumpto_export_netif.assign_attributes(
        kind: :veth_routed,
        enable: true,
        max_tx: 0,
        max_rx: 0
      )
      jumpto_export_netif.save! if jumpto_export_netif.changed? || jumpto_export_netif.new_record?

      jumpto_ip = IpAddress.find_or_initialize_by(ip_addr: '203.0.113.130')
      jumpto_ip.assign_attributes(
        prefix: 32,
        size: 1,
        network: jumpto_network,
        user: nil,
        network_interface: jumpto_export_netif
      )
      jumpto_ip.save! if jumpto_ip.changed? || jumpto_ip.new_record?

      HostIpAddress.find_or_initialize_by(
        ip_address: jumpto_ip,
        ip_addr: jumpto_ip.ip_addr
      ).tap do |host_ip|
        host_ip.auto_add = true
        host_ip.order = nil
        host_ip.user_created = false
        host_ip.save! if host_ip.changed? || host_ip.new_record?
      end

      jumpto_vps_dip = ensure_dataset_in_pool(
        user,
        webui_pool,
        'webui-jumpto-vps-dataset'
      )
      jumpto_vps = Vps.find_or_initialize_by(hostname: 'webui-jumpto-vps')
      jumpto_vps.assign_attributes(
        user: user,
        node: node,
        os_template: primary_template,
        dns_resolver: DnsResolver.first,
        dataset_in_pool: jumpto_vps_dip,
        user_namespace_map: userns_map,
        object_state: :active,
        confirmed: :confirmed,
        manage_hostname: true
      )
      jumpto_vps.save! if jumpto_vps.changed? || jumpto_vps.new_record?

      VpsCurrentStatus.find_or_initialize_by(vps: jumpto_vps).tap do |status|
        status.status = true
        status.is_running = false
        status.in_rescue_mode = false
        status.halted = false
        status.update_count = 1
        status.uptime = 0
        status.process_count = 0
        status.cpus = 1
        status.cpu_idle = 100.0
        status.cpu_user = 0.0
        status.cpu_nice = 0.0
        status.cpu_system = 0.0
        status.cpu_iowait = 0.0
        status.cpu_irq = 0.0
        status.cpu_softirq = 0.0
        status.loadavg1 = 0.0
        status.loadavg5 = 0.0
        status.loadavg15 = 0.0
        status.total_memory = 1024
        status.used_memory = 0
        status.total_swap = 0
        status.used_swap = 0
        status.total_diskspace = 10_240
        status.used_diskspace = 0
        status.save! if status.changed? || status.new_record?
      end

      jumpto_dns_zone = DnsZone.find_or_initialize_by(
        name: 'webui-jumpto.example.test.'
      )
      jumpto_dns_zone.assign_attributes(
        user: user,
        label: 'Webui Jumpto Zone',
        email: 'hostmaster@example.test',
        default_ttl: 3600,
        enabled: true,
        original_enabled: true,
        dnssec_enabled: false,
        zone_role: :forward_role,
        zone_source: :internal_source,
        confirmed: :confirmed
      )
      jumpto_dns_zone.save! if jumpto_dns_zone.changed? || jumpto_dns_zone.new_record?

      fixture_storage_dip = ensure_dataset_in_pool(
        user,
        webui_pool,
        'webui-fixture-storage-dataset'
      )
      fixture_snapshot = Snapshot.find_or_initialize_by(
        dataset: fixture_storage_dip.dataset,
        name: 'webui-fixture-snapshot'
      )
      fixture_snapshot.assign_attributes(
        label: 'Webui Fixture Snapshot',
        confirmed: :confirmed
      )
      fixture_snapshot.save! if fixture_snapshot.changed? || fixture_snapshot.new_record?

      fixture_snapshot_in_pool = SnapshotInPool.find_or_initialize_by(
        snapshot: fixture_snapshot,
        dataset_in_pool: fixture_storage_dip
      )
      fixture_snapshot_in_pool.confirmed = :confirmed
      fixture_snapshot_in_pool.save! if fixture_snapshot_in_pool.changed? || fixture_snapshot_in_pool.new_record?

      fixture_network = Network.find_or_initialize_by(
        address: '203.0.113.136',
        prefix: 29
      )
      fixture_network.assign_attributes(
        ip_version: 4,
        label: 'Webui Fixture Network',
        managed: false,
        primary_location: Location.find(${toString location.id}),
        role: :public_access,
        purpose: :any,
        split_access: :user_split,
        split_prefix: 32
      )
      fixture_network.save! if fixture_network.changed? || fixture_network.new_record?

      LocationNetwork.find_or_initialize_by(
        location: Location.find(${toString location.id}),
        network: fixture_network
      ).tap do |locnet|
        locnet.primary = true
        locnet.priority = 20
        locnet.autopick = true
        locnet.userpick = true
        locnet.save! if locnet.changed? || locnet.new_record?
      end

      fixture_free_ip = IpAddress.find_or_initialize_by(ip_addr: '203.0.113.137')
      fixture_free_ip.assign_attributes(
        prefix: 32,
        size: 1,
        network: fixture_network,
        user: user,
        network_interface: nil
      )
      fixture_free_ip.save! if fixture_free_ip.changed? || fixture_free_ip.new_record?

      HostIpAddress.find_or_initialize_by(
        ip_address: fixture_free_ip,
        ip_addr: fixture_free_ip.ip_addr
      ).tap do |host_ip|
        host_ip.auto_add = true
        host_ip.order = nil
        host_ip.user_created = false
        host_ip.save! if host_ip.changed? || host_ip.new_record?
      end

      support_vps_dip = ensure_dataset_in_pool(
        user,
        webui_pool,
        'webui-fixture-support-vps-dataset'
      )
      support_vps = Vps.find_or_initialize_by(hostname: 'webui-fixture-support-vps')
      support_vps.assign_attributes(
        user: user,
        node: node,
        os_template: primary_template,
        dns_resolver: DnsResolver.first,
        dataset_in_pool: support_vps_dip,
        user_namespace_map: userns_map,
        object_state: :active,
        confirmed: :confirmed,
        manage_hostname: true
      )
      support_vps.save! if support_vps.changed? || support_vps.new_record?

      support_netif = NetworkInterface.find_or_initialize_by(
        vps: support_vps,
        name: 'eth0'
      )
      support_netif.assign_attributes(
        kind: :veth_routed,
        enable: true,
        max_tx: 0,
        max_rx: 0
      )
      support_netif.save! if support_netif.changed? || support_netif.new_record?

      fixture_assigned_ip = IpAddress.find_or_initialize_by(ip_addr: '203.0.113.138')
      fixture_assigned_ip.assign_attributes(
        prefix: 32,
        size: 1,
        network: fixture_network,
        user: user,
        network_interface: support_netif
      )
      fixture_assigned_ip.save! if fixture_assigned_ip.changed? || fixture_assigned_ip.new_record?

      support_host_ip = HostIpAddress.find_or_initialize_by(
        ip_address: fixture_assigned_ip,
        ip_addr: fixture_assigned_ip.ip_addr
      )
      support_host_ip.auto_add = true
      support_host_ip.order = 0
      support_host_ip.user_created = false
      support_host_ip.save! if support_host_ip.changed? || support_host_ip.new_record?

      support_assignment = IpAddressAssignment.find_or_initialize_by(
        ip_address: fixture_assigned_ip,
        vps: support_vps,
        to_date: nil
      )
      support_assignment.assign_attributes(
        user: user,
        ip_addr: fixture_assigned_ip.ip_addr,
        ip_prefix: fixture_assigned_ip.prefix,
        from_date: Time.now - 3600,
        reconstructed: false
      )
      support_assignment.save! if support_assignment.changed? || support_assignment.new_record?

      fixture_dns_zone = DnsZone.find_or_initialize_by(
        name: 'webui-fixture.example.test.'
      )
      fixture_dns_zone.assign_attributes(
        user: user,
        label: 'Webui Fixture Zone',
        email: 'hostmaster@example.test',
        default_ttl: 3600,
        enabled: true,
        original_enabled: true,
        dnssec_enabled: false,
        zone_role: :forward_role,
        zone_source: :internal_source,
        confirmed: :confirmed
      )
      fixture_dns_zone.save! if fixture_dns_zone.changed? || fixture_dns_zone.new_record?

      fixture_dns_record = DnsRecord.find_or_initialize_by(
        dns_zone: fixture_dns_zone,
        name: 'www',
        record_type: 'A'
      )
      fixture_dns_record.assign_attributes(
        content: fixture_assigned_ip.ip_addr,
        ttl: 3600,
        enabled: true,
        original_enabled: true,
        confirmed: :confirmed,
        managed: false,
        user: nil
      )
      fixture_dns_record.save! if fixture_dns_record.changed? || fixture_dns_record.new_record?

      support_mailbox = Mailbox.find_or_initialize_by(label: 'Webui Fixture Mailbox')
      support_mailbox.assign_attributes(
        server: 'mail.example.test',
        port: 993,
        enable_ssl: true,
        user: 'webui-fixture',
        password: 'webui-fixture-password'
      )
      support_mailbox.save! if support_mailbox.changed? || support_mailbox.new_record?

      support_incident = IncidentReport.find_or_initialize_by(
        user: user,
        vps: support_vps,
        subject: 'Webui Fixture Incident'
      )
      support_incident.assign_attributes(
        filed_by: admin,
        ip_address_assignment: support_assignment,
        mailbox: support_mailbox,
        codename: 'WEBUI-FIXTURE',
        text: 'Deterministic webui browser fixture incident.',
        detected_at: Time.now - 1800,
        reported_at: Time.now - 1700,
        vps_action: :none
      )
      support_incident.save! if support_incident.changed? || support_incident.new_record?

      oom_rule = OomReportRule.find_or_initialize_by(
        vps: support_vps,
        cgroup_pattern: '/'
      )
      oom_rule.action = :notify
      oom_rule.save! if oom_rule.changed? || oom_rule.new_record?

      oom_report = OomReport.unscoped.find_or_initialize_by(
        vps: support_vps,
        invoked_by_pid: 1234,
        cgroup: '/'
      )
      oom_report.assign_attributes(
        oom_report_rule: oom_rule,
        processed: true,
        ignored: false,
        invoked_by_name: 'webui-fixture',
        killed_name: 'webui-killed',
        killed_pid: 1235,
        count: 1,
        reported_at: Time.now - 1200,
        created_at: Time.now - 1200
      )
      oom_report.save! if oom_report.changed? || oom_report.new_record?

      pools_by_filesystem = Pool
        .where(filesystem: [
          ${builtins.toJSON "tank/ct"},
          ${builtins.toJSON "tank/webui-node1-secondary"},
          ${builtins.toJSON "tank/webui-node2"}
        ])
        .index_by(&:filesystem)

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
          'publicKeys' => ([public_key] + extra_public_keys).map do |pubkey|
            {
              'id' => pubkey.id,
              'label' => pubkey.label,
              'autoAdd' => pubkey.auto_add
            }
          end,
          'userData' => {
            'id' => user_data.id,
            'label' => user_data.label
          },
          'userDataItems' => ([user_data] + extra_user_data).map do |data|
            {
              'id' => data.id,
              'label' => data.label,
              'format' => data.format
            }
          end,
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
          'alternateUserNamespaceMap' => {
            'id' => alternate_userns_map.id,
            'label' => alternate_userns_map.label
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
        'users' => {
          'secondary' => {
            'id' => secondary_user.id,
            'username' => secondary_user.login,
            'password' => 'webuiSecondaryPassword',
            'publicKey' => {
              'id' => secondary_public_key.id,
              'label' => secondary_public_key.label
            },
            'userData' => {
              'id' => secondary_user_data.id,
              'label' => secondary_user_data.label,
              'format' => secondary_user_data.format
            },
            'userNamespaceMap' => {
              'id' => secondary_userns_map.id,
              'label' => secondary_userns_map.label
            }
          }
        },
        'location' => {
          'id' => ${toString location.id},
          'label' => ${builtins.toJSON location.label}
        },
        'environment' => {
          'id' => env.id,
          'label' => env.label
        },
        'environments' => {
          'primary' => {
            'id' => env.id,
            'label' => env.label
          },
          'secondary' => {
            'id' => node2.location.environment.id,
            'label' => node2.location.environment.label
          }
        },
        'locations' => {
          'primary' => {
            'id' => ${toString location.id},
            'label' => ${builtins.toJSON location.label}
          },
          'secondary' => {
            'id' => node2.location.id,
            'label' => node2.location.label
          }
        },
        'node' => {
          'id' => node.id,
          'name' => node.name,
          'domainName' => node.domain_name,
          'locationId' => node.location_id
        },
        'cluster' => {
          'nodes' => {
            'node1' => {
              'id' => node.id,
              'name' => node.name,
              'domainName' => node.domain_name,
              'locationId' => node.location_id
            },
            'node2' => {
              'id' => node2.id,
              'name' => node2.name,
              'domainName' => node2.domain_name,
              'locationId' => node2.location_id
            }
          },
          'pools' => {
            'node1Primary' => pools_by_filesystem[${builtins.toJSON "tank/ct"}] && {
              'id' => pools_by_filesystem[${builtins.toJSON "tank/ct"}].id,
              'filesystem' => pools_by_filesystem[${builtins.toJSON "tank/ct"}].filesystem,
              'nodeId' => pools_by_filesystem[${builtins.toJSON "tank/ct"}].node_id
            },
            'node1Secondary' => pools_by_filesystem[${builtins.toJSON "tank/webui-node1-secondary"}] && {
              'id' => pools_by_filesystem[${builtins.toJSON "tank/webui-node1-secondary"}].id,
              'filesystem' => pools_by_filesystem[${builtins.toJSON "tank/webui-node1-secondary"}].filesystem,
              'nodeId' => pools_by_filesystem[${builtins.toJSON "tank/webui-node1-secondary"}].node_id
            },
            'node2Primary' => pools_by_filesystem[${builtins.toJSON "tank/webui-node2"}] && {
              'id' => pools_by_filesystem[${builtins.toJSON "tank/webui-node2"}].id,
              'filesystem' => pools_by_filesystem[${builtins.toJSON "tank/webui-node2"}].filesystem,
              'nodeId' => pools_by_filesystem[${builtins.toJSON "tank/webui-node2"}].node_id
            }
          }
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
          },
          'fixtures' => {
            'jumpto' => {
              'id' => jumpto_vps.id,
              'hostname' => jumpto_vps.hostname,
              'nodeId' => jumpto_vps.node_id,
              'datasetInPoolId' => jumpto_vps.dataset_in_pool_id
            },
            'support' => {
              'id' => support_vps.id,
              'hostname' => support_vps.hostname,
              'nodeId' => support_vps.node_id,
              'datasetInPoolId' => support_vps.dataset_in_pool_id
            }
          }
        },
        'storage' => {
          'dataset' => {
            'id' => fixture_storage_dip.dataset.id,
            'name' => fixture_storage_dip.dataset.name,
            'fullName' => fixture_storage_dip.dataset.full_name
          },
          'datasetInPool' => {
            'id' => fixture_storage_dip.id,
            'poolId' => fixture_storage_dip.pool_id
          },
          'snapshot' => {
            'id' => fixture_snapshot.id,
            'name' => fixture_snapshot.name,
            'label' => fixture_snapshot.label
          },
          'snapshotInPool' => {
            'id' => fixture_snapshot_in_pool.id
          }
        },
        'networking' => {
          'network' => {
            'id' => fixture_network.id,
            'cidr' => fixture_network.to_s,
            'label' => fixture_network.label
          },
          'ipAddresses' => {
            'free' => {
              'id' => fixture_free_ip.id,
              'addr' => fixture_free_ip.ip_addr
            },
            'assigned' => {
              'id' => fixture_assigned_ip.id,
              'addr' => fixture_assigned_ip.ip_addr,
              'networkInterfaceId' => support_netif.id,
              'assignmentId' => support_assignment.id
            }
          }
        },
        'dns' => {
          'zone' => {
            'id' => fixture_dns_zone.id,
            'name' => fixture_dns_zone.name,
            'label' => fixture_dns_zone.label
          },
          'record' => {
            'id' => fixture_dns_record.id,
            'name' => fixture_dns_record.name,
            'type' => fixture_dns_record.record_type,
            'content' => fixture_dns_record.content
          }
        },
        'support' => {
          'mailbox' => {
            'id' => support_mailbox.id,
            'label' => support_mailbox.label
          },
          'incidentReport' => {
            'id' => support_incident.id,
            'subject' => support_incident.subject,
            'vpsId' => support_vps.id
          },
          'oomReport' => {
            'id' => oom_report.id,
            'vpsId' => support_vps.id,
            'ruleId' => oom_rule.id
          }
        },
        'newsLog' => {
          'id' => news_log_id,
          'message' => news_log_message
        },
        'objectHistory' => {
          'id' => history.id,
          'eventType' => history.event_type,
          'message' => history_message
        },
        'transactionChain' => {
          'id' => readonly_chain_id.to_i,
          'transactionId' => readonly_transaction_id.to_i,
          'name' => 'webui_readonly',
          'label' => 'New login',
          'state' => 'done'
        },
        'transactions' => {
          'states' => webui_transactions,
          'userSession' => {
            'id' => readonly_session.id,
            'label' => readonly_session.label
          }
        },
        'jumpto' => {
          'textSearch' => 'webui',
          'ipSearch' => jumpto_ip.ip_addr,
          'user' => {
            'id' => user.id,
            'login' => user.login
          },
          'vps' => {
            'id' => jumpto_vps.id,
            'hostname' => jumpto_vps.hostname
          },
          'dnsZone' => {
            'id' => jumpto_dns_zone.id,
            'name' => jumpto_dns_zone.name
          },
          'export' => {
            'id' => jumpto_export.id
          },
          'network' => {
            'id' => jumpto_network.id,
            'cidr' => jumpto_network.to_s
          },
          'ipAddress' => {
            'id' => jumpto_ip.id,
            'addr' => jumpto_ip.ip_addr
          }
        }
      )
      fixture_stdout.flush
    '';

    baseMachines = import ../machines/cluster/2-node.nix args;
  in
  {
    name = "vpsadmin-webui";

    description = ''
      Boot a vpsAdmin cluster and exercise user/admin PHP web UI flows through
      Playwright. Existing scripts prepare node1 only; node2 is available for
      future scripts that explicitly start it.
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

    testScripts = {
      auth = {
        description = ''
          Run anonymous, authentication, session, and role menu browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui auth browser flow' do
            it 'passes Playwright auth tests' do
              run_playwright('auth', 'specs/auth.spec.cjs')
            end
          end
        '';
      };

      userns = {
        description = ''
          Run user namespace browser tests for user and admin roles.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui user namespace browser flow' do
            it 'passes Playwright user namespace tests' do
              run_playwright('userns', 'specs/userns.spec.cjs')
            end
          end
        '';
      };

      vps-lifecycle = {
        description = ''
          Run VPS lifecycle browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui VPS lifecycle browser flow' do
            it 'passes Playwright VPS lifecycle tests' do
              run_playwright('vps-lifecycle', 'specs/vps-lifecycle.spec.cjs')
            end
          end
        '';
      };

      vps-user-core = {
        description = ''
          Run user-mode VPS list, create, and detail form browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui user VPS core browser flow' do
            it 'passes Playwright user VPS core tests' do
              run_playwright('vps-user-core', 'specs/vps-user-core.spec.cjs')
            end
          end
        '';
      };

      vps-user-ops = {
        description = ''
          Run user-mode VPS side operation and console browser tests.
        '';
        script = webuiTestScriptCommon + ''
          def prepare_webui_component
            prepare_webui_cross_location_swap
          end

          describe 'webui user VPS side operation browser flow' do
            it 'passes Playwright user VPS side operation tests' do
              run_playwright('vps-user-ops', 'specs/vps-user-ops.spec.cjs')
            end
          end
        '';
      };

      vps-admin-core = {
        description = ''
          Run admin-mode VPS list, create, and detail form browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui admin VPS core browser flow' do
            it 'passes Playwright admin VPS core tests' do
              run_playwright('vps-admin-core', 'specs/vps-admin-core.spec.cjs')
            end
          end
        '';
      };

      vps-admin-ops = {
        description = ''
          Run admin-mode VPS long operation browser tests.
        '';
        script = webuiTestScriptCommon + ''
          def prepare_webui_component
            prepare_webui_admin_ops_cluster
          end

          describe 'webui admin VPS long operation browser flow' do
            it 'passes Playwright admin VPS long operation tests' do
              run_playwright('vps-admin-ops', 'specs/vps-admin-ops.spec.cjs')
            end
          end
        '';
      };

      navigation-readonly = {
        description = ''
          Run read-only overview, navigation, history, node, and transaction browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui read-only navigation browser flow' do
            it 'passes Playwright read-only navigation tests' do
              run_playwright('navigation-readonly', 'specs/navigation-readonly.spec.cjs')
            end
          end
        '';
      };

      jumpto = {
        description = ''
          Run admin jumpto browser search tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui admin jumpto browser flow' do
            it 'passes Playwright jumpto tests' do
              run_playwright('jumpto', 'specs/jumpto.spec.cjs')
            end
          end
        '';
      };

      transactions = {
        description = ''
          Run transaction list, filter, and chain detail browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui transactions browser flow' do
            it 'passes Playwright transaction tests' do
              run_playwright('transactions', 'specs/transactions.spec.cjs')
            end
          end
        '';
      };
    };
  }
)
