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
    webuiTestScriptCommon = common + ''
      require 'shellwords'
      require 'base64'

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

      def webui_pool_id
        row = services.mariadb_json_rows(sql: <<~SQL).first
          SELECT JSON_OBJECT('id', id)
          FROM pools
          WHERE filesystem = #{primary_pool_fs.inspect}
          LIMIT 1
        SQL

        row && row.fetch('id')
      end

      def ensure_webui_pool
        pool_id = webui_pool_id

        unless pool_id
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'webui-browser-vps',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          pool_id = pool.fetch('id')
        end

        wait_for_pool_online(services, pool_id)
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

          API_DIR="$api_dir" "$api_root/ruby-env-wrapped/bin/ruby" ${fixtureScript}
        SH

        JSON.parse(output.to_s.lines.last)
      end

      def write_playwright_fixtures(services, fixtures)
        encoded = Base64.strict_encode64(JSON.generate(fixtures))
        services.succeeds(
          "printf %s #{Shellwords.escape(encoded)} | base64 -d > #{WEBUI_FIXTURES}"
        )
      end

      def prepare_webui_playwright
        [services, node].each { |machine| start_webui_machine(machine) }
        services.wait_for_vpsadmin_api
        wait_for_webui
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        unlock_webui_transaction_signing_key
        ensure_webui_pool

        write_playwright_fixtures(
          services,
          create_webui_browser_fixtures(services)
        )
      end

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

      node = Node.find(${toString nodeSeed.id})

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
        'node' => {
          'id' => node.id,
          'name' => node.name,
          'domainName' => node.domain_name
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
