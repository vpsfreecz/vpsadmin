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

      def wait_for_webui_services_ready
        services.wait_for_vpsadmin_api
        services.wait_for_service('vpsadmin-rabbitmq-setup.service')
        services.wait_for_service('vpsadmin-supervisor.service')
        wait_for_webui
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

      def prepare_webui_runtime(_fixtures); end

      def prepare_webui_storage_runtime(storage)
        datasets = {}

        add_dataset = lambda do |id, full_name, pool_fs|
          return unless id && full_name && pool_fs

          datasets[Integer(id)] = {
            'full_name' => full_name,
            'pool_fs' => pool_fs
          }
        end

        if storage['dataset']
          add_dataset.call(
            storage['dataset']['id'],
            storage['dataset']['fullName'],
            storage.dig('datasetInPool', 'poolFilesystem')
          )
        end

        storage.fetch('datasets', {}).each_value do |dataset|
          add_dataset.call(
            dataset['id'],
            dataset['fullName'],
            dataset['poolFilesystem']
          )
        end

        storage.fetch('vps', {}).each_value do |vps|
          add_dataset.call(
            vps['datasetId'],
            vps['datasetFullName'],
            vps['datasetPoolFilesystem']
          )
          add_dataset.call(
            vps['childDatasetId'],
            vps['childDatasetFullName'],
            vps['childDatasetPoolFilesystem']
          )
        end

        dataset_lines = datasets
          .values
          .uniq
          .sort_by { |dataset| [dataset.fetch('pool_fs'), dataset.fetch('full_name')] }
          .map { |dataset| "#{dataset.fetch('pool_fs')}|#{dataset.fetch('full_name')}" }
          .join("\n")

        pool_lines = datasets
          .values
          .map { |dataset| dataset.fetch('pool_fs') }
          .uniq
          .sort
          .join("\n")

        vps_lines = storage
          .fetch('vps', {})
          .values
          .filter_map do |vps|
            next unless vps['id'] &&
              vps['datasetPoolFilesystem'] &&
              vps['userNamespaceMapId']

            [
              vps.fetch('id'),
              vps.fetch('datasetPoolFilesystem'),
              vps.fetch('userNamespaceMapId'),
              vps.fetch('uidMap', []).join(','),
              vps.fetch('gidMap', []).join(',')
            ].join('|')
          end
          .join("\n")

        snapshot_lines = storage
          .fetch('snapshots', {})
          .values
          .filter_map do |snapshot|
            dataset = datasets[Integer(snapshot.fetch('datasetId'))]
            next unless dataset

            "#{dataset.fetch('pool_fs')}|#{dataset.fetch('full_name')}|#{snapshot.fetch('name')}"
          end
          .uniq
          .sort
          .join("\n")

        node1.succeeds(<<~SH, timeout: 600)
          set -euo pipefail

          ensure_dataset() {
            local dataset="$1"

            if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then
              zfs create -p "$dataset"
            fi

            if ! zfs list -H -o name "$dataset" >/dev/null 2>&1; then
              echo "missing ZFS dataset after creation: $dataset" >&2
              exit 1
            fi

            mkdir -p "/$dataset/private"
          }

          while IFS='|' read -r pool_fs dataset_name; do
            [ -n "$pool_fs" ] || continue
            ensure_dataset "$pool_fs/$dataset_name"
          done <<'WEBUI_STORAGE_DATASETS'
          #{dataset_lines}
          WEBUI_STORAGE_DATASETS

          while IFS='|' read -r pool_fs; do
            [ -n "$pool_fs" ] || continue
            ensure_dataset "$pool_fs/vpsadmin/config"
            ensure_dataset "$pool_fs/vpsadmin/download"
            ensure_dataset "$pool_fs/vpsadmin/mount"
          done <<'WEBUI_STORAGE_POOLS'
          #{pool_lines}
          WEBUI_STORAGE_POOLS

          container_exists() {
            osctl -j ct show "$1" >/dev/null 2>&1
          }

          ensure_osctl_user() {
            local pool_name="$1"
            local user_name="$2"
            local uid_maps="$3"
            local gid_maps="$4"

            if osctl --pool "$pool_name" user show "$user_name" >/dev/null 2>&1; then
              return
            fi

            local user_args=(osctl --pool "$pool_name" user new)
            local uid_map
            local gid_map

            IFS=',' read -ra uid_map_args <<< "$uid_maps"
            for uid_map in "''${uid_map_args[@]}"; do
              [ -n "$uid_map" ] || continue
              user_args+=(--map-uid "$uid_map")
            done

            IFS=',' read -ra gid_map_args <<< "$gid_maps"
            for gid_map in "''${gid_map_args[@]}"; do
              [ -n "$gid_map" ] || continue
              user_args+=(--map-gid "$gid_map")
            done

            user_args+=("$user_name")
            "''${user_args[@]}"
          }

          while IFS='|' read -r vps_id pool_fs userns_map_id uid_maps gid_maps; do
            [ -n "$vps_id" ] || continue

            pool_name="''${pool_fs%%/*}"
            ensure_osctl_user "$pool_name" "$userns_map_id" "$uid_maps" "$gid_maps"

            if ! container_exists "$vps_id"; then
              osctl --pool "$pool_name" ct new \\
                --skip-image \\
                --user "$userns_map_id" \\
                --distribution debian \\
                --version latest \\
                --arch x86_64 \\
                "$vps_id"
              osctl --pool "$pool_name" ct mounts clear "$vps_id" >/dev/null 2>&1 || true
            fi
          done <<'WEBUI_STORAGE_VPSES'
          #{vps_lines}
          WEBUI_STORAGE_VPSES

          while IFS='|' read -r pool_fs dataset_name snapshot_name; do
            [ -n "$pool_fs" ] || continue
            ensure_dataset "$pool_fs/$dataset_name"

            if ! zfs list -H -t snapshot "$pool_fs/$dataset_name@$snapshot_name" >/dev/null 2>&1; then
              zfs snapshot "$pool_fs/$dataset_name@$snapshot_name"
            fi
          done <<'WEBUI_STORAGE_SNAPSHOTS'
          #{snapshot_lines}
          WEBUI_STORAGE_SNAPSHOTS
        SH

        node1.succeeds('sv restart nodectld', timeout: 60)
        wait_for_running_nodectld(node1)
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
        wait_for_webui_services_ready
        wait_for_running_nodectld(node1)
        wait_for_webui_node_ready(node1, node1_id)
        unlock_webui_transaction_signing_key
        ensure_webui_default_pool
        prepare_webui_component

        fixtures = create_webui_browser_fixtures(services)
        prepare_webui_runtime(fixtures)
        fixtures
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

      def run_playwright(script_name, *specs, timeout: 1800)
        raise ArgumentError, 'at least one Playwright spec is required' if specs.empty?

        safe_name = script_name.gsub(/[^A-Za-z0-9_.-]/, '-')
        spec_args = specs.map { |spec| Shellwords.escape(spec) }.join(' ')

        wait_for_webui_transaction_chains_idle

        playwright_failed = false

        begin
          services.succeeds(<<~SH, timeout: timeout)
            set -euo pipefail

            export CI=1
            export HOME=/tmp/vpsadmin-webui-playwright-home-#{safe_name}
            export PLAYWRIGHT_BROWSERS_PATH=${playwrightBrowsers}
            export WEBUI_BASE_URL=http://webui.vpsadmin.test
            export VPSADMIN_WEBUI_FIXTURES=#{WEBUI_FIXTURES}
            export VPSADMIN_WEBUI_REVISION="$(${pkgs.jq}/bin/jq --raw-output .revision /etc/vpsadmin/build-info.json)"
            result_dir=/tmp/vpsadmin-webui-playwright-results-#{safe_name}

            rm -rf "$HOME" "$result_dir"
            mkdir -p "$HOME"

            cd ${playwrightSuite}
            set +e
            ${playwrightRunner}/bin/vpsadmin-webui-playwright test #{spec_args} \
              --config=${playwrightSuite}/playwright.config.cjs \
              --output="$result_dir"
            status=$?
            set -e

            if [ "$status" -ne 0 ]; then
              echo "[run_playwright] Playwright failed for #{safe_name}; artifacts in $result_dir"
              find "$result_dir" -name error-context.md -print | while IFS= read -r context; do
                echo "[run_playwright] error context: $context"
                sed -n '1,240p' "$context"
              done
              find "$result_dir" -name trace.zip -print -o -name '*.png' -print \
                | sed 's/^/[run_playwright] artifact: /'
            fi

            exit "$status"
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

      plugin_root = File.expand_path('../plugins', ENV.fetch('API_DIR'))
      %w[payments requests outage_reports monitoring newslog webui].each do |plugin|
        Dir[File.join(plugin_root, plugin, 'api', 'models', '*.rb')]
          .sort
          .each { |path| require path }
      end

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

      def ensure_dataset_in_pool(user, pool, name, parent: nil, vps: nil)
        full_name = parent ? "#{parent.full_name}/#{name}" : name
        dataset = Dataset.find_by(user: user, full_name: full_name) ||
          Dataset.new(name: name, user: user)
        dataset.assign_attributes(
          name: name,
          parent: parent,
          user: user,
          vps: vps,
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

      def ensure_webui_pool_record(node, label:, filesystem:, role:)
        pool = Pool.find_or_initialize_by(filesystem: filesystem)
        pool.assign_attributes(
          node: node,
          label: label,
          role: role,
          is_open: true,
          max_datasets: 100,
          refquota_check: true,
          state: :online,
          scan: :none
        )
        pool.save! if pool.changed? || pool.new_record?
        ensure_pool_dataset_properties(pool)
        pool
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

      def clear_fixture_locks(*records)
        records.compact.each do |record|
          ResourceLock
            .where(resource: record.class.name, row_id: record.id)
            .delete_all
        end
      end

      def ensure_snapshot_fixture(dataset_in_pool, name:, label:, history_id:)
        snapshot = Snapshot.find_or_initialize_by(
          dataset: dataset_in_pool.dataset,
          name: name
        )
        snapshot.assign_attributes(
          label: label,
          history_id: history_id,
          confirmed: :confirmed,
          created_at: Time.now - history_id,
          updated_at: Time.now - history_id
        )
        snapshot.save! if snapshot.changed? || snapshot.new_record?

        if dataset_in_pool.dataset.current_history_id < history_id
          dataset_in_pool.dataset.update!(current_history_id: history_id)
        end

        SnapshotInPool.find_or_initialize_by(
          snapshot: snapshot,
          dataset_in_pool: dataset_in_pool
        ).tap do |sip|
          sip.confirmed = :confirmed
          sip.reference_count ||= 0
          sip.save! if sip.changed? || sip.new_record?
        end

        snapshot
      end

      def ensure_snapshot_download_fixture(user, snapshot, pool, key)
        dl = SnapshotDownload.find_or_initialize_by(
          secret_key: "webui-storage-#{key}"
        )
        dl.assign_attributes(
          user: user,
          snapshot: snapshot,
          pool: pool,
          file_name: "webui-storage-#{key}.tar.gz",
          format: :archive,
          size: 2048,
          sha256sum: '0' * 64,
          expiration_date: Time.now + 7 * 24 * 60 * 60,
          object_state: :active,
          confirmed: :confirmed
        )
        dl.save! if dl.changed? || dl.new_record?
        snapshot.update!(snapshot_download: dl)
        dl
      end

      def ensure_storage_vps(user, dataset_in_pool, hostname, node, template, resolver, userns_map)
        vps = Vps.find_or_initialize_by(hostname: hostname)
        vps.assign_attributes(
          user: user,
          node: node,
          os_template: template,
          dns_resolver: resolver,
          dataset_in_pool: dataset_in_pool,
          user_namespace_map: userns_map,
          object_state: :active,
          confirmed: :confirmed,
          manage_hostname: true
        )
        vps.save! if vps.changed? || vps.new_record?
        dataset_in_pool.dataset.update!(vps: vps) if dataset_in_pool.dataset.vps_id != vps.id

        VpsCurrentStatus.find_or_initialize_by(vps: vps).tap do |status|
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

        clear_fixture_locks(vps, dataset_in_pool, dataset_in_pool.dataset)
        vps
      end

      def ensure_mount_fixture(vps, dataset_in_pool, mountpoint, enabled: true)
        mount = Mount.find_or_initialize_by(vps: vps, dst: mountpoint)
        mount.assign_attributes(
          dataset_in_pool: dataset_in_pool,
          mode: 'rw',
          mount_opts: "",
          umount_opts: "",
          mount_type: 'dataset',
          enabled: enabled,
          master_enabled: true,
          user_editable: true,
          current_state: enabled ? :mounted : :unmounted,
          object_state: :active,
          confirmed: :confirmed
        )
        mount.save! if mount.changed? || mount.new_record?
        clear_fixture_locks(vps, mount, dataset_in_pool)
        mount
      end

      def ensure_storage_export_network(location)
        network = Network.find_or_initialize_by(address: '198.51.101.0', prefix: 24)
        network.assign_attributes(
          ip_version: 4,
          label: 'Webui Storage Export Network',
          managed: true,
          primary_location: location,
          role: :private_access,
          purpose: :export,
          split_access: :no_access,
          split_prefix: 32
        )
        network.save! if network.changed? || network.new_record?

        LocationNetwork.find_or_initialize_by(location: location, network: network).tap do |locnet|
          locnet.primary = true
          locnet.priority = 5
          locnet.autopick = true
          locnet.userpick = true
          locnet.save! if locnet.changed? || locnet.new_record?
        end

        network
      end

      def ensure_ip_fixture(network, addr, user: nil, network_interface: nil)
        ip = IpAddress.find_or_initialize_by(ip_addr: addr)
        ip.assign_attributes(
          prefix: network.split_prefix,
          size: 1,
          network: network,
          user: user,
          network_interface: network_interface
        )
        ip.save! if ip.changed? || ip.new_record?

        HostIpAddress.find_or_initialize_by(
          ip_address: ip,
          ip_addr: ip.ip_addr
        ).tap do |host_ip|
          host_ip.auto_add = true
          host_ip.order = nil
          host_ip.user_created = false
          host_ip.save! if host_ip.changed? || host_ip.new_record?
        end

        ip
      end

      def ensure_host_ip_fixture(ip, addr, order: nil, user_created: false)
        HostIpAddress.find_or_initialize_by(
          ip_address: ip,
          ip_addr: addr
        ).tap do |host_ip|
          host_ip.auto_add = true
          host_ip.order = order
          host_ip.user_created = user_created
          host_ip.save! if host_ip.changed? || host_ip.new_record?
        end
      end

      def ensure_dns_zone_fixture(
        name,
        user: nil,
        label: nil,
        source: :internal_source,
        role: :forward_role,
        email: 'hostmaster@example.test',
        dnssec_enabled: false,
        enabled: true,
        reverse_network_address: nil,
        reverse_network_prefix: nil
      )
        zone = DnsZone.find_or_initialize_by(name: name)
        zone.assign_attributes(
          user: user,
          label: label || name,
          email: source == :internal_source ? email : nil,
          default_ttl: 3600,
          enabled: enabled,
          original_enabled: enabled,
          dnssec_enabled: dnssec_enabled,
          zone_role: role,
          zone_source: source,
          reverse_network_address: reverse_network_address,
          reverse_network_prefix: reverse_network_prefix,
          confirmed: :confirmed
        )
        zone.save! if zone.changed? || zone.new_record?
        zone
      end

      def ensure_dns_record_fixture(
        zone,
        name,
        type,
        content,
        ttl: 3600,
        priority: nil,
        comment: "",
        enabled: true,
        user: nil,
        managed: false
      )
        record = DnsRecord.find_or_initialize_by(
          dns_zone: zone,
          name: name,
          record_type: type
        )
        record.assign_attributes(
          content: content,
          ttl: ttl,
          priority: priority,
          comment: comment,
          enabled: enabled,
          original_enabled: enabled,
          confirmed: :confirmed,
          managed: managed,
          user: user
        )
        record.save! if record.changed? || record.new_record?
        record
      end

      def reset_dns_record_token(record)
        if record.update_token
          token = record.update_token
          record.update!(update_token: nil)
          token.destroy!
        end
      end

      def cleanup_dns_zone_fixture(name)
        zone = DnsZone.find_by(name: name)
        return unless zone

        clear_fixture_locks(zone)
        zone.dns_server_zones.delete_all
        zone.dns_zone_transfers.delete_all
        zone.dnssec_records.delete_all
        zone.dns_records.find_each do |record|
          record.update_token&.destroy!
          record.destroy!
        end
        zone.dns_record_logs.update_all(dns_zone_id: nil)
        zone.destroy!
      end

      def ensure_export_fixture(user, dataset_in_pool, server_ip, key, enabled: true, host_ip: nil)
        export = Export.find_or_initialize_by(
          dataset_in_pool: dataset_in_pool,
          snapshot_in_pool_clone_n: 0
        )
        export_attrs = {
          snapshot_in_pool_clone: nil,
          user: user,
          all_vps: false,
          path: "/export/#{dataset_in_pool.dataset.full_name}",
          rw: true,
          sync: true,
          subtree_check: false,
          root_squash: false,
          threads: 8,
          enabled: enabled,
          object_state: :active,
          confirmed: :confirmed
        }
        if export.new_record?
          Uuid.generate_for_new_record! do |uuid|
            export.assign_attributes(export_attrs)
            export.uuid = uuid
            export.save!
            export
          end
        else
          export.assign_attributes(export_attrs)
          export.uuid ||= Uuid.generate!
          export.save! if export.changed?
        end

        netif = NetworkInterface.find_or_initialize_by(export: export, name: 'eth0')
        netif.assign_attributes(
          kind: :veth_routed,
          enable: true,
          max_tx: 0,
          max_rx: 0
        )
        netif.save! if netif.changed? || netif.new_record?

        server_ip.update!(network_interface: netif, user: nil)
        server_host_ip = server_ip.host_ip_addresses.first || HostIpAddress.create!(
          ip_address: server_ip,
          ip_addr: server_ip.ip_addr
        )

        export.export_hosts.where.not(ip_address_id: host_ip&.id).find_each(&:destroy!)
        export_host = nil
        if host_ip
          export_host = ExportHost.find_or_initialize_by(
            export: export,
            ip_address: host_ip
          )
          export_host.assign_attributes(
            rw: true,
            sync: true,
            subtree_check: false,
            root_squash: false
          )
          export_host.save! if export_host.changed? || export_host.new_record?
        end

        clear_fixture_locks(export, netif, server_ip, server_host_ip, export_host)
        {
          export: export,
          network_interface: netif,
          server_ip: server_ip,
          host_ip: server_host_ip,
          export_host: export_host
        }
      end

      def ensure_outage_fixture(
        summary:,
        description:,
        state:,
        outage_type:,
        impact_type:,
        begins_at:,
        duration:,
        node:,
        handler:,
        vps: nil,
        export: nil
      )
        translation = OutageTranslation.find_by(
          summary: summary,
          outage_update_id: nil
        )
        outage = translation&.outage || Outage.new
        outage.assign_attributes(
          begins_at: begins_at,
          finished_at: nil,
          duration: duration,
          state: state,
          outage_type: outage_type,
          impact_type: impact_type,
          auto_resolve: false
        )
        outage.save! if outage.changed? || outage.new_record?

        Language.find_each do |lang|
          localized_summary = lang.code == 'en' ? summary : "#{summary} #{lang.code}"
          localized_description = lang.code == 'en' ? description : "#{description} #{lang.code}"

          OutageTranslation.find_or_initialize_by(
            outage: outage,
            outage_update: nil,
            language: lang
          ).tap do |tr|
            tr.summary = localized_summary
            tr.description = localized_description
            tr.save! if tr.changed? || tr.new_record?
          end
        end

        update = outage.outage_updates.order(:id).first || OutageUpdate.new(outage: outage)
        update.assign_attributes(
          reported_by: handler,
          reporter_name: handler.full_name,
          begins_at: begins_at,
          duration: duration,
          state: state,
          impact_type: impact_type
        )
        update.save! if update.changed? || update.new_record?

        Language.find_each do |lang|
          localized_summary = lang.code == 'en' ? summary : "#{summary} #{lang.code}"
          localized_description = lang.code == 'en' ? description : "#{description} #{lang.code}"

          OutageTranslation.find_or_initialize_by(
            outage: nil,
            outage_update: update,
            language: lang
          ).tap do |tr|
            tr.summary = localized_summary
            tr.description = localized_description
            tr.save! if tr.changed? || tr.new_record?
          end
        end

        OutageEntity
          .where(outage: outage)
          .where.not(name: 'Node', row_id: node.id)
          .destroy_all
        OutageEntity.find_or_create_by!(
          outage: outage,
          name: 'Node',
          row_id: node.id
        )

        OutageHandler
          .where(outage: outage)
          .where.not(user_id: handler.id)
          .destroy_all
        OutageHandler.find_or_initialize_by(outage: outage, user: handler).tap do |h|
          h.full_name = handler.full_name
          h.save! if h.changed? || h.new_record?
        end

        if state == :staged
          outage.outage_vpses.destroy_all
          outage.outage_exports.destroy_all
          outage.outage_users.destroy_all
        else
          affected_vps_count = 0
          affected_export_count = 0

          if vps
            OutageVps.find_or_initialize_by(outage: outage, vps: vps).tap do |out|
              out.user = vps.user
              out.node = vps.node
              out.location = vps.node.location
              out.environment = vps.node.location.environment
              out.direct = true
              out.save! if out.changed? || out.new_record?
            end
            affected_vps_count = 1
          else
            outage.outage_vpses.destroy_all
          end

          if export
            OutageExport.find_or_initialize_by(outage: outage, export: export).tap do |out|
              out.user = export.user
              out.node = node
              out.location = node.location
              out.environment = node.location.environment
              out.save! if out.changed? || out.new_record?
            end
            affected_export_count = 1
          else
            outage.outage_exports.destroy_all
          end

          if vps || export
            affected_user = (vps || export).user
            OutageUser.find_or_initialize_by(outage: outage, user: affected_user).tap do |out|
              out.vps_count = affected_vps_count
              out.export_count = affected_export_count
              out.save! if out.changed? || out.new_record?
            end
            outage.outage_users.where.not(user_id: affected_user.id).destroy_all
          else
            outage.outage_users.destroy_all
          end
        end

        outage.reload
      end

      def cleanup_security_advisory_fixtures
        ids = SecurityAdvisoryCve
          .where('cve_id LIKE ?', 'CVE-2099-%')
          .pluck(:security_advisory_id)

        ids.concat(
          SecurityAdvisory
            .where('name LIKE ?', 'Webui Security Advisory%')
            .pluck(:id)
        )
        ids.concat(
          SecurityAdvisory
            .where('name LIKE ?', 'Webui Browser Advisory%')
            .pluck(:id)
        )

        SecurityAdvisory.where(id: ids.uniq).find_each(&:destroy!)
      end

      def advisory_translation_attrs(summary, description, response, lang)
        suffix = lang.code == 'en' ? "" : " #{lang.code}"

        {
          summary: "#{summary}#{suffix}",
          description: "#{description}#{suffix}",
          response: "#{response}#{suffix}"
        }
      end

      def ensure_security_advisory_fixture(
        name:,
        cves:,
        summary:,
        description:,
        response:,
        node_statuses:,
        published_at: nil,
        publish: false,
        admin:
      )
        advisory = SecurityAdvisory.create!(
          name: name,
          created_by: admin,
          published_at: published_at
        )

        advisory.update_cves!(cves.join(', '))

        Language.find_each do |lang|
          advisory.security_advisory_translations.create!(
            advisory_translation_attrs(summary, description, response, lang)
              .merge(language: lang)
          )
        end

        SecurityAdvisory.advisory_nodes.each do |node|
          status = node_statuses.fetch(node.id) do
            {
              state: :not_affected,
              vulnerable_until: nil,
              mitigated_since: nil,
              notes: {}
            }
          end

          node_status = advisory.security_advisory_node_statuses.create!(
            {
              node: node,
              state: status.fetch(:state),
              vulnerable_until: status[:vulnerable_until],
              mitigated_since: status[:mitigated_since]
            }
          )

          Language.find_each do |lang|
            note = status.fetch(:notes, {})[lang.code.to_sym]
            next if note.nil? || note.empty?

            node_status.security_advisory_node_status_translations.create!(
              language: lang,
              note: note
            )
          end
        end

        if publish
          advisory.publish!(
            expected_content_revision: advisory.content_revision,
            send_mail: false,
            published_by: admin,
            published_at: published_at
          )
        end

        advisory.reload
      end

      def security_advisory_fixture_json(advisory)
        en = advisory
          .security_advisory_translations
          .joins(:language)
          .find_by!(languages: { code: 'en' })

        {
          'id' => advisory.id,
          'state' => advisory.state,
          'name' => advisory.name,
          'cves' => advisory.security_advisory_cves.order(:cve_id).pluck(:cve_id),
          'summary' => en.summary,
          'description' => en.description,
          'response' => en.response,
          'affectedUserCount' => advisory.affected_user_count,
          'affectedVpsCount' => advisory.affected_vps_count,
          'affectedNodeCount' => advisory.affected_node_count
        }
      end

      def ensure_monitored_event_fixture(
        monitor:,
        object:,
        user:,
        state: :confirmed,
        value: 'webui fixture value'
      )
        event = MonitoredEvent.find_or_initialize_by(
          monitor_name: monitor.to_s,
          class_name: object.class.name,
          row_id: object.id
        )
        event.assign_attributes(
          user: user,
          state: state,
          access_level: 0,
          last_report_at: Time.now - 900,
          saved_until: nil,
          action_state: nil,
          alert_count: 0,
          created_at: Time.now - 3600,
          updated_at: Time.now - 1800
        )
        event.save! if event.changed? || event.new_record?

        event.monitored_event_logs.delete_all
        event.monitored_event_logs.create!(
          passed: false,
          value: value,
          created_at: Time.now - 1200
        )

        event.monitored_event_states.delete_all
        event.monitored_event_states.create!(
          state: event.state,
          created_at: Time.now - 1200
        )

        event.reload
      end

      def ensure_webui_user(
        login:,
        full_name:,
        email:,
        password:,
        env:,
        language:,
        monthly_payment: 0,
        time_zone: nil
      )
        user = User.find_or_initialize_by(login: login)
        user.assign_attributes(
          full_name: full_name,
          email: email,
          time_zone: time_zone,
          level: 2,
          language: language,
          enable_basic_auth: true,
          enable_token_auth: true,
          enable_oauth2_auth: true,
          enable_single_sign_on: true,
          enable_new_login_notification: true,
          enable_multi_factor_auth: false,
          preferred_session_length: 20 * 60,
          preferred_logout_all: false,
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
          VALUES (#{user.id}, #{monthly_payment.to_i}, NULL, #{quoted_now})
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
      admin_managed_user = ensure_webui_user(
        login: 'webui-admin-managed-user',
        full_name: 'Webui Admin Managed User',
        email: 'webui-admin-managed@example.test',
        password: 'webuiAdminManagedPassword',
        env: env,
        language: language,
        monthly_payment: 100
      )
      hard_deleted_request_user = User.unscoped.find_by(
        login: 'webui-hard-deleted-request-user'
      )
      if hard_deleted_request_user
        hard_deleted_request_user.update_column(
          :object_state,
          User.object_states[:active]
        )
      end
      hard_deleted_request_user = ensure_webui_user(
        login: 'webui-hard-deleted-request-user',
        full_name: 'Webui Hard Deleted Request User',
        email: 'webui-hard-deleted-request-user@example.test',
        password: 'webuiHardDeletedRequestUserPassword',
        env: env,
        language: language
      )
      time_zone_tip_set_user = ensure_webui_user(
        login: 'webui-time-zone-tip-set',
        full_name: 'Webui Time Zone Tip Set',
        email: 'webui-time-zone-tip-set@example.test',
        password: 'webuiTimeZoneTipSetPassword',
        env: env,
        language: language,
        time_zone: nil
      )
      time_zone_tip_dismiss_user = ensure_webui_user(
        login: 'webui-time-zone-tip-dismiss',
        full_name: 'Webui Time Zone Tip Dismiss',
        email: 'webui-time-zone-tip-dismiss@example.test',
        password: 'webuiTimeZoneTipDismissPassword',
        env: env,
        language: language,
        time_zone: nil
      )
      time_zone_tip_utc_user = ensure_webui_user(
        login: 'webui-time-zone-tip-utc',
        full_name: 'Webui Time Zone Tip UTC',
        email: 'webui-time-zone-tip-utc@example.test',
        password: 'webuiTimeZoneTipUtcPassword',
        env: env,
        language: language,
        time_zone: nil
      )

      if defined?(WebuiUserSetting)
        WebuiUserSetting
          .where(
            user: [
              time_zone_tip_set_user,
              time_zone_tip_dismiss_user,
              time_zone_tip_utc_user
            ],
            namespace: 'tips'
          )
          .delete_all
      end

      quoted_now = ActiveRecord::Base.connection.quote(Time.now)
      reminder_expiration = Time.now + 90 * 24 * 60 * 60
      [user, secondary_user, admin_managed_user].each do |reminder_user|
        reminder_user.update_columns(
          expiration_date: reminder_expiration,
          remind_after_date: nil
        )
      end

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

        [user, secondary_user, admin_managed_user].each do |resource_user|
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

        [user, secondary_user, admin_managed_user].each do |resource_user|
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

          [user, secondary_user, admin_managed_user].each do |resource_user|
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

      admin_member_prefix = 'Webui Admin Managed'
      admin_managed_public_key = UserPublicKey.find_or_initialize_by(
        user: admin_managed_user,
        label: "#{admin_member_prefix} Fixture Key"
      )
      admin_managed_public_key.key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFwebuiadminmanaged webui-admin-managed@test'
      admin_managed_public_key.auto_add = false
      admin_managed_public_key.save!

      UserPublicKey
        .where(user: admin_managed_user)
        .where('label LIKE ?', "#{admin_member_prefix} Key Added%")
        .find_each(&:destroy!)
      MetricsAccessToken
        .where(user: admin_managed_user)
        .where('metric_prefix LIKE ?', 'webui_admin_managed%')
        .find_each(&:destroy!)

      admin_session_agent = UserAgent.find_or_create!(
        'webui-playwright-admin-managed-session'
      )
      UserSession
        .where(user: admin_managed_user, label: [
          "#{admin_member_prefix} Session",
          "#{admin_member_prefix} Session Edited"
        ])
        .delete_all
      admin_user_session = UserSession.create!(
        user: admin_managed_user,
        user_agent: admin_session_agent,
        auth_type: 'token',
        api_ip_addr: '198.51.100.50',
        client_ip_addr: '198.51.100.51',
        client_version: 'webui-playwright-admin-managed',
        label: "#{admin_member_prefix} Session",
        request_count: 5,
        last_request_at: Time.now - 90
      )
      UserMailRoleRecipient.where(user: admin_managed_user).delete_all
      UserMailTemplateRecipient.where(user: admin_managed_user).delete_all

      [
        ['default_currency', 'String', 'CZK'],
        ['conversion_rates', 'Hash', {}]
      ].each do |name, data_type, value|
        SysConfig.find_or_initialize_by(
          category: 'plugin_payments',
          name: name
        ).tap do |cfg|
          cfg.value = value
          cfg.data_type = data_type
          cfg.min_user_level = 99
          cfg.save! if cfg.changed? || cfg.new_record?
        end
      end

      UserPayment.where(user: admin_managed_user).delete_all
      admin_managed_user.user_account.update!(
        monthly_payment: 100,
        paid_until: nil,
        updated_at: Time.now
      )

      admin_redirect_payment = UserPayment.new(
        user: admin_managed_user,
        accounted_by: admin,
        amount: 100,
        from_date: Time.now - 60 * 60 * 24 * 30,
        to_date: Time.now + 60 * 60 * 24 * 30,
        created_at: Time.now - 600
      )
      admin_redirect_payment.save!

      admin_incoming_tx = 'webui-admin-managed-incoming'
      admin_old_incoming_ids = IncomingPayment
        .where(transaction_id: admin_incoming_tx)
        .pluck(:id)
      UserPayment
        .where(incoming_payment_id: admin_old_incoming_ids)
        .delete_all if admin_old_incoming_ids.any?
      IncomingPayment.where(id: admin_old_incoming_ids).delete_all
      admin_incoming_payment = IncomingPayment.create!(
        transaction_id: admin_incoming_tx,
        date: Date.today,
        amount: 100,
        currency: 'CZK',
        account_name: 'Webui Admin Managed Sender',
        user_ident: admin_managed_user.login,
        user_message: 'webui admin managed payment',
        vs: admin_managed_user.id.to_s,
        transaction_type: 'webui-admin-managed',
        state: :unmatched,
        created_at: Time.now - 300
      )

      admin_resource_package = ClusterResourcePackage
        .where(label: "#{admin_member_prefix} Package", user_id: nil, environment_id: nil)
        .first_or_initialize
      admin_resource_package.save! if admin_resource_package.changed? || admin_resource_package.new_record?
      admin_resource_package_item = ClusterResourcePackageItem.find_or_initialize_by(
        cluster_resource_package: admin_resource_package,
        cluster_resource: ClusterResource.find_by!(name: 'cpu')
      )
      admin_resource_package_item.value = 1
      admin_resource_package_item.save! if admin_resource_package_item.changed? || admin_resource_package_item.new_record?
      UserClusterResourcePackage
        .where(user: admin_managed_user, cluster_resource_package: admin_resource_package)
        .find_each(&:destroy!)

      UserRequest
        .where('change_reason LIKE ?', "#{admin_member_prefix} approval%")
        .delete_all
      create_admin_change_request = lambda do |suffix|
        request = ChangeRequest.new(
          user: admin_managed_user,
          state: :awaiting,
          api_ip_addr: '192.0.2.31',
          api_ip_ptr: 'webui-admin-approval.example.test',
          client_ip_addr: '198.51.100.31',
          client_ip_ptr: 'webui-admin-client.example.test',
          change_reason: "#{admin_member_prefix} approval #{suffix}",
          full_name: "#{admin_member_prefix} Approval #{suffix}"
        )
        request.save!
        request
      end
      admin_approval_approve = create_admin_change_request.call('approve')
      admin_approval_deny = create_admin_change_request.call('deny')
      admin_approval_ignore = create_admin_change_request.call('ignore')
      hard_deleted_request_reason = 'Webui hard-deleted user approval denied'
      UserRequest.where(change_reason: hard_deleted_request_reason).delete_all
      hard_deleted_request = ChangeRequest.new(
        user: hard_deleted_request_user,
        state: :denied,
        api_ip_addr: '192.0.2.32',
        api_ip_ptr: 'webui-hard-deleted-approval.example.test',
        client_ip_addr: '198.51.100.32',
        client_ip_ptr: 'webui-hard-deleted-client.example.test',
        change_reason: hard_deleted_request_reason,
        full_name: 'Webui Hard Deleted Requested Name',
        email: 'webui-hard-deleted-requested@example.test',
        address: 'Webui Hard Deleted Requested Address'
      )
      hard_deleted_request.save!
      hard_deleted_request_user.update_column(
        :object_state,
        User.object_states[:hard_delete]
      )

      self_service_prefix = 'Webui Self-Service'
      UserPublicKey
        .where(user: user)
        .where('label LIKE ?', "#{self_service_prefix} Key%")
        .find_each(&:destroy!)
      UserTotpDevice
        .where(user: user)
        .where('label LIKE ?', "#{self_service_prefix} TOTP%")
        .find_each(&:destroy!)
      MetricsAccessToken
        .where(user: user)
        .where('metric_prefix LIKE ?', 'webui_self_service%')
        .find_each(&:destroy!)

      self_service_webauthn_external_id = 'webui-self-service-passkey'
      WebauthnCredential
        .where(user: user)
        .where(
          'external_id = ? OR label LIKE ?',
          self_service_webauthn_external_id,
          "#{self_service_prefix} Passkey%"
        )
        .find_each(&:destroy!)
      self_service_webauthn = WebauthnCredential.create!(
        user: user,
        external_id: self_service_webauthn_external_id,
        public_key: 'webui-self-service-public-key',
        label: "#{self_service_prefix} Passkey",
        sign_count: 0,
        enabled: true
      )

      self_service_device_agent = UserAgent.find_or_create!(
        'Mozilla/5.0 (X11; Linux x86_64) Firefox/128.0 WebuiSelfService'
      )
      UserDevice
        .where(user: user, user_agent: self_service_device_agent)
        .find_each(&:destroy!)
      self_service_known_device = Token.for_new_record!(Time.now + UserDevice::LIFETIME) do |token|
        UserDevice.create!(
          user: user,
          token: token,
          client_ip_addr: '192.0.2.20',
          client_ip_ptr: 'webui-self-service.example.test',
          user_agent: self_service_device_agent,
          known: true,
          skip_multi_factor_auth_until: Time.now + 3600,
          last_seen_at: Time.now - 60
        )
      end

      self_service_session_agent = UserAgent.find_or_create!(
        'webui-playwright-self-service-session'
      )
      UserSession
        .where(user: user, label: [
          "#{self_service_prefix} Session",
          "#{self_service_prefix} Session Edited"
        ])
        .delete_all
      self_service_session = UserSession.create!(
        user: user,
        user_agent: self_service_session_agent,
        auth_type: 'token',
        api_ip_addr: '198.51.100.40',
        client_ip_addr: '198.51.100.41',
        client_version: 'webui-playwright-self-service',
        label: "#{self_service_prefix} Session",
        request_count: 3,
        last_request_at: Time.now - 90
      )

      payment_instructions_template =
        'Payment instructions for <%= user.login %>: monthly=<%= monthly_payment %>'
      SysConfig.find_or_initialize_by(
        category: 'plugin_payments',
        name: 'payment_instructions'
      ).tap do |cfg|
        cfg.value = payment_instructions_template
        cfg.data_type = 'Text'
        cfg.min_user_level = 99
        cfg.save! if cfg.changed? || cfg.new_record?
      end
      self_service_monthly_payment = ActiveRecord::Base.connection.select_value(<<~SQL)
        SELECT monthly_payment FROM user_accounts WHERE user_id = #{user.id}
      SQL
      self_service_payment_instructions =
        "Payment instructions for #{user.login}: monthly=#{self_service_monthly_payment}"

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
      reported_boot = node
        .node_kernel_events
        .boot
        .node_report
        .where.not(node_kernel_evidence_id: nil)
        .order(observed_before: :desc, id: :desc)
        .first!
      reconstructed_boot = node.node_kernel_events.find_or_initialize_by(
        event_type: :boot,
        source: :reconstructed_node_status,
        boot_id: 'webui-reconstructed-boot'
      )
      reconstructed_boot.assign_attributes(
        confidence: :inferred,
        booted_at: reported_boot.booted_at - 86_400,
        booted_release: reported_boot.booted_release,
        reported_release: reported_boot.reported_release,
        effective_at: reported_boot.booted_at - 86_400,
        observed_before: reported_boot.observed_before - 86_400,
        current: false,
        kernel_evidence: nil
      )
      reconstructed_boot.save! if reconstructed_boot.changed? || reconstructed_boot.new_record?

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
      readonly_transaction_label = Transaction.find(readonly_transaction_id).label

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
          'transactionLabel' => tx&.label,
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
      cluster_admin_prefix = 'Webui Cluster Admin'
      cluster_admin_os_family = primary_template.os_family

      MaintenanceLock
        .where(class_name: 'Cluster', row_id: nil, active: true)
        .find_each do |lock|
          lock.unlock!(nil)
        rescue ActiveRecord::RecordInvalid
          lock.update!(active: false)
        end

      DnsResolver
        .where('label LIKE ?', "#{cluster_admin_prefix} DNS%")
        .find_each do |resolver|
          next if resolver.in_use?

          clear_fixture_locks(resolver)
          resolver.destroy!
        end

      ClusterResourcePackage
        .where(user_id: nil, environment_id: nil)
        .where('label LIKE ?', "#{cluster_admin_prefix} Package%")
        .find_each(&:destroy!)

      OsTemplate
        .where('label LIKE ?', "#{cluster_admin_prefix} Template%")
        .find_each do |template|
          template.destroy! unless template.in_use?
        end

      NewsLog
        .where('message LIKE ?', "#{cluster_admin_prefix} News%")
        .delete_all

      HelpBox
        .where('content LIKE ?', "#{cluster_admin_prefix} Help%")
        .delete_all

      cluster_admin_env = Environment.find_or_initialize_by(
        label: "#{cluster_admin_prefix} Environment"
      )
      cluster_admin_env.assign_attributes(
        domain: 'cluster-admin.vpsadmin.test',
        description: 'Webui cluster admin coverage environment',
        can_create_vps: true,
        can_destroy_vps: true,
        vps_lifetime: 0,
        max_vps_count: 25,
        user_ip_ownership: false
      )
      cluster_admin_env.save! if cluster_admin_env.changed? || cluster_admin_env.new_record?

      Location
        .where('label LIKE ?', "#{cluster_admin_prefix} Created Location%")
        .find_each do |loc|
          loc.location_networks.destroy_all
          loc.destroy! if loc.nodes.empty?
        end

      cluster_admin_location = Location.find_or_initialize_by(
        label: "#{cluster_admin_prefix} Location A"
      )
      cluster_admin_location.assign_attributes(
        environment: cluster_admin_env,
        domain: 'cluster-admin-a',
        description: 'Webui cluster admin coverage location A',
        remote_console_server: 'http://console.vpsadmin.test',
        has_ipv6: false
      )
      cluster_admin_location.save! if cluster_admin_location.changed? || cluster_admin_location.new_record?

      cluster_admin_other_location = Location.find_or_initialize_by(
        label: "#{cluster_admin_prefix} Location B"
      )
      cluster_admin_other_location.assign_attributes(
        environment: cluster_admin_env,
        domain: 'cluster-admin-b',
        description: 'Webui cluster admin coverage location B',
        remote_console_server: 'http://console.vpsadmin.test',
        has_ipv6: false
      )
      cluster_admin_other_location.save! if cluster_admin_other_location.changed? || cluster_admin_other_location.new_record?

      def ensure_cluster_admin_network(address, label, primary_location)
        network = Network.find_or_initialize_by(address: address, prefix: 29)
        network.assign_attributes(
          ip_version: 4,
          label: label,
          managed: true,
          primary_location: primary_location,
          role: :public_access,
          purpose: :vps,
          split_access: :no_access,
          split_prefix: 32
        )
        network.save! if network.changed? || network.new_record?
        network
      end

      cluster_admin_network = ensure_cluster_admin_network(
        '198.51.110.0',
        "#{cluster_admin_prefix} Network A",
        cluster_admin_location
      )
      cluster_admin_other_network = ensure_cluster_admin_network(
        '198.51.110.8',
        "#{cluster_admin_prefix} Network B",
        cluster_admin_location
      )
      cluster_admin_ip_network = ensure_cluster_admin_network(
        '198.51.111.0',
        "#{cluster_admin_prefix} IP Add Network",
        cluster_admin_location
      )

      cluster_admin_ip_addr = '198.51.111.2'
      IpAddress.where(ip_addr: cluster_admin_ip_addr).find_each do |ip|
        clear_fixture_locks(ip)
        HostIpAddress.where(ip_address: ip).delete_all
        IpAddressAssignment.where(ip_address: ip).delete_all
        ip.destroy!
      end

      LocationNetwork
        .where(
          location: cluster_admin_other_location,
          network: [cluster_admin_network, cluster_admin_other_network]
        )
        .destroy_all

      [
        cluster_admin_network,
        cluster_admin_other_network,
        cluster_admin_ip_network
      ].each_with_index do |network, idx|
        network.location_networks.where.not(location: cluster_admin_location).update_all(primary: nil)

        LocationNetwork.find_or_initialize_by(
          location: cluster_admin_location,
          network: network
        ).tap do |locnet|
          locnet.primary = true
          locnet.priority = 30 + idx
          locnet.autopick = true
          locnet.userpick = true
          locnet.save! if locnet.changed? || locnet.new_record?
        end

        network.update!(primary_location: cluster_admin_location)
      end

      webui_pool = Pool.where(node: node, role: Pool.roles[:hypervisor]).order(:id).first
      raise 'webui hypervisor pool not found' unless webui_pool
      storage_primary_pool = ensure_webui_pool_record(
        node,
        label: 'webui-storage-primary',
        filesystem: 'tank/webui-storage-primary',
        role: :primary
      )
      storage_backup_pool = ensure_webui_pool_record(
        node,
        label: 'webui-storage-backup',
        filesystem: 'tank/webui-storage-backup',
        role: :backup
      )
      Pool.where(role: [
        Pool.roles[:hypervisor],
        Pool.roles[:primary],
        Pool.roles[:backup]
      ]).find_each do |pool|
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
      support_vps.update_columns(
        expiration_date: reminder_expiration,
        remind_after_date: nil
      )

      VpsCurrentStatus.find_or_initialize_by(vps: support_vps).tap do |status|
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

      [
        'webui-user-primary-create.example.test.',
        'webui-user-secondary-create.example.test.',
        'webui-admin-primary-create.example.test.',
        'webui-admin-secondary-create.example.test.'
      ].each { |zone_name| cleanup_dns_zone_fixture(zone_name) }

      DnsTsigKey
        .where(name: [
          "#{user.id}-webui-user-tsig-create",
          "#{admin_managed_user.id}-webui-admin-tsig-create"
        ])
        .destroy_all

      networking_reverse_zone = ensure_dns_zone_fixture(
        '113.0.203.in-addr.arpa.',
        label: 'Webui Networking Reverse Zone',
        role: :reverse_role,
        reverse_network_address: '203.0.113.0',
        reverse_network_prefix: 24
      )

      networking_network = Network.find_or_initialize_by(
        address: '203.0.113.160',
        prefix: 27
      )
      networking_network.assign_attributes(
        ip_version: 4,
        label: 'Webui Networking Coverage Network',
        managed: false,
        primary_location: Location.find(${toString location.id}),
        role: :public_access,
        purpose: :any,
        split_access: :user_split,
        split_prefix: 32
      )
      networking_network.save! if networking_network.changed? || networking_network.new_record?

      networking_multihost_network = Network.find_or_initialize_by(
        address: '203.0.113.192',
        prefix: 28
      )
      networking_multihost_network.assign_attributes(
        ip_version: 4,
        label: 'Webui Networking Multi-host Network',
        managed: false,
        primary_location: Location.find(${toString location.id}),
        role: :public_access,
        purpose: :any,
        split_access: :user_split,
        split_prefix: 30
      )
      networking_multihost_network.save! if networking_multihost_network.changed? || networking_multihost_network.new_record?

      [networking_network, networking_multihost_network].each_with_index do |net, idx|
        LocationNetwork.find_or_initialize_by(
          location: Location.find(${toString location.id}),
          network: net
        ).tap do |locnet|
          locnet.primary = true
          locnet.priority = 30 + idx
          locnet.autopick = true
          locnet.userpick = true
          locnet.save! if locnet.changed? || locnet.new_record?
        end
      end

      make_networking_vps = lambda do |key|
        root_dip = ensure_dataset_in_pool(
          user,
          webui_pool,
          "webui-networking-#{key}-root"
        )
        vps = ensure_storage_vps(
          user,
          root_dip,
          "webui-networking-#{key}",
          node,
          primary_template,
          DnsResolver.first,
          userns_map
        )
        netif = NetworkInterface.find_or_initialize_by(
          vps: vps,
          name: 'eth0'
        )
        netif.assign_attributes(
          kind: :veth_routed,
          enable: true,
          max_tx: 0,
          max_rx: 0
        )
        netif.save! if netif.changed? || netif.new_record?
        clear_fixture_locks(vps, netif)

        { vps: vps, netif: netif }
      end

      networking_vps = {
        list: make_networking_vps.call('list'),
        user_route_assign: make_networking_vps.call('user-route-assign'),
        user_route_unassign: make_networking_vps.call('user-route-unassign'),
        user_host_assign: make_networking_vps.call('user-host-assign'),
        user_host_unassign: make_networking_vps.call('user-host-unassign'),
        user_ptr: make_networking_vps.call('user-ptr'),
        admin_route_only: make_networking_vps.call('admin-route-only'),
        admin_route_host: make_networking_vps.call('admin-route-host'),
        admin_route_unassign: make_networking_vps.call('admin-route-unassign'),
        admin_host_assign: make_networking_vps.call('admin-host-assign'),
        admin_host_unassign: make_networking_vps.call('admin-host-unassign'),
        admin_ptr: make_networking_vps.call('admin-ptr'),
        dns_transfer: make_networking_vps.call('dns-transfer')
      }

      networking_ip_specs = {
        list_free: ['203.0.113.161', user, nil, nil],
        user_route_assign: ['203.0.113.162', user, nil, nil],
        admin_route_only: ['203.0.113.163', nil, nil, nil],
        admin_route_host: ['203.0.113.164', nil, nil, nil],
        user_route_unassign: ['203.0.113.165', user, networking_vps.fetch(:user_route_unassign).fetch(:netif), 0],
        admin_route_unassign: ['203.0.113.166', user, networking_vps.fetch(:admin_route_unassign).fetch(:netif), 0],
        user_host_assign: ['203.0.113.167', user, networking_vps.fetch(:user_host_assign).fetch(:netif), nil],
        user_host_unassign: ['203.0.113.168', user, networking_vps.fetch(:user_host_unassign).fetch(:netif), 0],
        admin_host_assign: ['203.0.113.169', user, networking_vps.fetch(:admin_host_assign).fetch(:netif), nil],
        admin_host_unassign: ['203.0.113.170', user, networking_vps.fetch(:admin_host_unassign).fetch(:netif), 0],
        user_ptr: ['203.0.113.171', user, networking_vps.fetch(:user_ptr).fetch(:netif), 0],
        admin_ptr: ['203.0.113.172', user, networking_vps.fetch(:admin_ptr).fetch(:netif), 0],
        admin_owner_edit: ['203.0.113.173', nil, nil, nil],
        dns_transfer: ['203.0.113.174', user, networking_vps.fetch(:dns_transfer).fetch(:netif), 0]
      }

      networking_ips = networking_ip_specs.to_h do |key, (addr, owner, netif, host_order)|
        ip = IpAddress.find_or_initialize_by(ip_addr: addr)
        ip.assign_attributes(
          prefix: networking_network.split_prefix,
          size: 1,
          network: networking_network,
          user: owner,
          charged_environment: owner ? env : nil,
          network_interface: netif,
          reverse_dns_zone: networking_reverse_zone
        )
        ip.save! if ip.changed? || ip.new_record?

        host_ip = ensure_host_ip_fixture(ip, addr, order: host_order)
        clear_fixture_locks(ip, host_ip, netif, netif&.vps)

        [key, { ip: ip, host_ip: host_ip }]
      end

      networking_assignment_specs = {
        user_route_unassign: networking_vps.fetch(:user_route_unassign).fetch(:vps),
        admin_route_unassign: networking_vps.fetch(:admin_route_unassign).fetch(:vps),
        user_host_assign: networking_vps.fetch(:user_host_assign).fetch(:vps),
        user_host_unassign: networking_vps.fetch(:user_host_unassign).fetch(:vps),
        admin_host_assign: networking_vps.fetch(:admin_host_assign).fetch(:vps),
        admin_host_unassign: networking_vps.fetch(:admin_host_unassign).fetch(:vps),
        user_ptr: networking_vps.fetch(:user_ptr).fetch(:vps),
        admin_ptr: networking_vps.fetch(:admin_ptr).fetch(:vps),
        dns_transfer: networking_vps.fetch(:dns_transfer).fetch(:vps)
      }

      networking_assignments = networking_assignment_specs.to_h do |key, vps|
        ip = networking_ips.fetch(key).fetch(:ip)
        assignment = IpAddressAssignment.find_or_initialize_by(
          ip_address: ip,
          vps: vps,
          to_date: nil
        )
        assignment.assign_attributes(
          user: vps.user,
          ip_addr: ip.ip_addr,
          ip_prefix: ip.prefix,
          from_date: Time.now - 1800,
          reconstructed: false
        )
        assignment.save! if assignment.changed? || assignment.new_record?
        [key, assignment]
      end

      networking_multihost_user_ip = IpAddress.find_or_initialize_by(ip_addr: '203.0.113.196')
      networking_multihost_user_ip.assign_attributes(
        prefix: networking_multihost_network.split_prefix,
        size: 4,
        network: networking_multihost_network,
        user: user,
        charged_environment: env,
        network_interface: nil,
        reverse_dns_zone: networking_reverse_zone
      )
      networking_multihost_user_ip.save! if networking_multihost_user_ip.changed? || networking_multihost_user_ip.new_record?
      HostIpAddress
        .where(ip_address: networking_multihost_user_ip, ip_addr: '203.0.113.197')
        .delete_all
      networking_multihost_user_host = ensure_host_ip_fixture(
        networking_multihost_user_ip,
        '203.0.113.196'
      )

      networking_multihost_admin_ip = IpAddress.find_or_initialize_by(ip_addr: '203.0.113.200')
      networking_multihost_admin_ip.assign_attributes(
        prefix: networking_multihost_network.split_prefix,
        size: 4,
        network: networking_multihost_network,
        user: nil,
        charged_environment: nil,
        network_interface: nil,
        reverse_dns_zone: networking_reverse_zone
      )
      networking_multihost_admin_ip.save! if networking_multihost_admin_ip.changed? || networking_multihost_admin_ip.new_record?
      HostIpAddress
        .where(ip_address: networking_multihost_admin_ip, ip_addr: '203.0.113.201')
        .delete_all
      networking_multihost_admin_host = ensure_host_ip_fixture(
        networking_multihost_admin_ip,
        '203.0.113.200'
      )
      clear_fixture_locks(
        networking_multihost_user_ip,
        networking_multihost_user_host,
        networking_multihost_admin_ip,
        networking_multihost_admin_host
      )

      now = Time.now
      networking_accounting = NetworkInterfaceMonthlyAccounting.find_or_initialize_by(
        network_interface: networking_vps.fetch(:list).fetch(:netif),
        user: user,
        year: now.year,
        month: now.month
      )
      networking_accounting.assign_attributes(
        bytes_in: 64 * 1024 * 1024,
        bytes_out: 32 * 1024 * 1024,
        packets_in: 6400,
        packets_out: 3200,
        created_at: now - 600,
        updated_at: now - 300
      )
      networking_accounting.save! if networking_accounting.changed? || networking_accounting.new_record?

      networking_monitor = NetworkInterfaceMonitor.find_or_initialize_by(
        network_interface: networking_vps.fetch(:list).fetch(:netif)
      )
      networking_monitor.assign_attributes(
        bytes: 96 * 1024,
        bytes_in: 64 * 1024,
        bytes_out: 32 * 1024,
        bytes_in_readout: 1024 * 1024,
        bytes_out_readout: 512 * 1024,
        packets: 96,
        packets_in: 64,
        packets_out: 32,
        packets_in_readout: 640,
        packets_out_readout: 320,
        delta: 10,
        created_at: now - 60,
        updated_at: now
      )
      networking_monitor.save! if networking_monitor.changed? || networking_monitor.new_record?

      dns_server = DnsServer.find_or_initialize_by(name: 'webui-ns1.example.test')
      dns_server.assign_attributes(
        node: node,
        ipv4_addr: '203.0.113.10',
        ipv6_addr: nil,
        hidden: false,
        enable_user_dns_zones: false,
        user_dns_zone_type: :secondary_type
      )
      dns_server.save! if dns_server.changed? || dns_server.new_record?

      hidden_dns_server = DnsServer.find_or_initialize_by(name: 'webui-hidden-ns.example.test')
      hidden_dns_server.assign_attributes(
        node: node,
        ipv4_addr: '203.0.113.11',
        ipv6_addr: nil,
        hidden: true,
        enable_user_dns_zones: false,
        user_dns_zone_type: :secondary_type
      )
      hidden_dns_server.save! if hidden_dns_server.changed? || hidden_dns_server.new_record?

      dns_zone_names = {
        user_update: 'webui-dns-user-update.example.test.',
        user_delete: 'webui-dns-user-delete.example.test.',
        user_record_create: 'webui-dns-user-record-create.example.test.',
        user_record_edit: 'webui-dns-user-record-edit.example.test.',
        user_record_toggle: 'webui-dns-user-record-toggle.example.test.',
        user_record_ddns: 'webui-dns-user-record-ddns.example.test.',
        user_record_delete: 'webui-dns-user-record-delete.example.test.',
        user_dnssec: 'webui-dns-user-dnssec.example.test.',
        user_transfer_log: 'webui-dns-user-transfer.example.test.',
        admin_update: 'webui-dns-admin-update.example.test.',
        admin_delete: 'webui-dns-admin-delete.example.test.',
        admin_server_zone_add: 'webui-dns-admin-server-add.example.test.',
        admin_server_zone_delete: 'webui-dns-admin-server-delete.example.test.',
        admin_transfer_add: 'webui-dns-admin-transfer-add.example.test.',
        admin_transfer_delete: 'webui-dns-admin-transfer-delete.example.test.',
        admin_record: 'webui-dns-admin-record.example.test.',
        admin_dnssec: '168.192.in-addr.arpa.',
        admin_log: 'webui-dns-admin-log.example.test.'
      }

      dns_zones = dns_zone_names.to_h do |key, name|
        attrs = case key
                when :user_transfer_log
                  { user: user, source: :external_source }
                when :admin_record, :admin_log
                  { user: nil }
                when :admin_dnssec
                  {
                    user: nil,
                    role: :reverse_role,
                    reverse_network_address: '192.168.0.0',
                    reverse_network_prefix: 16,
                    dnssec_enabled: true
                  }
                else
                  { user: key.to_s.start_with?('user_') ? user : user }
                end

        [key, ensure_dns_zone_fixture(
          name,
          **attrs,
          label: "Webui DNS #{key}",
          dnssec_enabled: attrs.fetch(:dnssec_enabled, false)
        )]
      end

      dns_records = {
        user_update: ensure_dns_record_fixture(
          dns_zones.fetch(:user_update),
          'www',
          'A',
          networking_ips.fetch(:list_free).fetch(:ip).ip_addr
        ),
        user_edit: ensure_dns_record_fixture(
          dns_zones.fetch(:user_record_edit),
          'edit',
          'A',
          '198.51.100.20'
        ),
        user_toggle: ensure_dns_record_fixture(
          dns_zones.fetch(:user_record_toggle),
          'toggle',
          'A',
          '198.51.100.21',
          enabled: true
        ),
        user_ddns: ensure_dns_record_fixture(
          dns_zones.fetch(:user_record_ddns),
          'ddns',
          'A',
          '198.51.100.22'
        ),
        user_delete: ensure_dns_record_fixture(
          dns_zones.fetch(:user_record_delete),
          'delete-me',
          'A',
          '198.51.100.23'
        ),
        admin_edit: ensure_dns_record_fixture(
          dns_zones.fetch(:admin_record),
          'edit',
          'A',
          '198.51.100.30',
          user: nil
        ),
        admin_toggle: ensure_dns_record_fixture(
          dns_zones.fetch(:admin_record),
          'toggle',
          'A',
          '198.51.100.31',
          enabled: true,
          user: nil
        ),
        admin_ddns: ensure_dns_record_fixture(
          dns_zones.fetch(:admin_record),
          'ddns',
          'A',
          '198.51.100.32',
          user: nil
        ),
        admin_delete: ensure_dns_record_fixture(
          dns_zones.fetch(:admin_record),
          'delete-me',
          'A',
          '198.51.100.33',
          user: nil
        )
      }
      dns_records.each_value { |record| reset_dns_record_token(record) }

      DnssecRecord.find_or_initialize_by(
        dns_zone: dns_zones.fetch(:user_dnssec),
        keyid: 12345
      ).tap do |record|
        record.dnskey_algorithm = 13
        record.dnskey_pubkey = 'AwEAAc3WebuiUserKey'
        record.ds_algorithm = 13
        record.ds_digest_type = 2
        record.ds_digest = 'a' * 64
        record.save! if record.changed? || record.new_record?
      end

      DnssecRecord.find_or_initialize_by(
        dns_zone: dns_zones.fetch(:admin_dnssec),
        keyid: 54321
      ).tap do |record|
        record.dnskey_algorithm = 13
        record.dnskey_pubkey = 'AwEAAc3WebuiAdminKey'
        record.ds_algorithm = 13
        record.ds_digest_type = 2
        record.ds_digest = 'b' * 64
        record.save! if record.changed? || record.new_record?
      end

      dns_tsig_keys = {
        user_list: DnsTsigKey.find_or_initialize_by(name: 'webui-user-tsig-list'),
        user_delete: DnsTsigKey.find_or_initialize_by(name: 'webui-user-tsig-delete'),
        admin_list: DnsTsigKey.find_or_initialize_by(name: 'webui-admin-tsig-list'),
        admin_delete: DnsTsigKey.find_or_initialize_by(name: 'webui-admin-tsig-delete'),
        transfer: DnsTsigKey.find_or_initialize_by(name: 'webui-transfer-tsig')
      }
      dns_tsig_keys.each do |key, record|
        record.assign_attributes(
          user: key.to_s.start_with?('admin') ? admin_managed_user : user,
          algorithm: 'hmac-sha256',
          secret: 'd2VidWktZXk='
        )
        record.save! if record.changed? || record.new_record?
      end

      dns_server_zone_log = DnsServerZone.find_or_initialize_by(
        dns_zone: dns_zones.fetch(:user_transfer_log),
        dns_server: dns_server
      )
      dns_server_zone_log.assign_attributes(
        zone_type: :secondary_type,
        confirmed: :confirmed,
        serial: 2026051901,
        loaded_at: now - 1200,
        last_check_at: now - 600,
        last_transfer_at: now - 600,
        last_transfer_status: :success,
        last_transfer_primary_addr: networking_ips.fetch(:dns_transfer).fetch(:host_ip).ip_addr,
        last_transfer_serial: 2026051901
      )
      dns_server_zone_log.save! if dns_server_zone_log.changed? || dns_server_zone_log.new_record?

      dns_server_zone_delete = DnsServerZone.find_or_initialize_by(
        dns_zone: dns_zones.fetch(:admin_server_zone_delete),
        dns_server: dns_server
      )
      dns_server_zone_delete.assign_attributes(
        zone_type: :secondary_type,
        confirmed: :confirmed,
        serial: 2026051902
      )
      dns_server_zone_delete.save! if dns_server_zone_delete.changed? || dns_server_zone_delete.new_record?

      dns_transfer_delete = DnsZoneTransfer.find_or_initialize_by(
        dns_zone: dns_zones.fetch(:admin_transfer_delete),
        host_ip_address: networking_ips.fetch(:dns_transfer).fetch(:host_ip)
      )
      dns_transfer_delete.assign_attributes(
        peer_type: :secondary_type,
        dns_tsig_key: dns_tsig_keys.fetch(:transfer),
        confirmed: :confirmed
      )
      dns_transfer_delete.save! if dns_transfer_delete.changed? || dns_transfer_delete.new_record?

      DnsServerZoneTransferLog
        .where(event_key: ['webui-transfer-user', 'webui-transfer-admin'])
        .delete_all
      user_transfer_log = DnsServerZoneTransferLog.create!(
        dns_server_zone: dns_server_zone_log,
        event_at: now - 500,
        event_key: 'webui-transfer-user',
        status: :success,
        primary_addr: networking_ips.fetch(:dns_transfer).fetch(:host_ip).ip_addr,
        serial: 2026051901,
        reason_code: 'webui-ok',
        reason: 'Webui transfer fixture',
        message: 'Webui transfer fixture succeeded',
        raw_message: 'webui transfer raw message',
        source_cursor: 'webui-transfer-cursor'
      )
      admin_transfer_log = DnsServerZoneTransferLog.create!(
        dns_server_zone: dns_server_zone_log,
        event_at: now - 400,
        event_key: 'webui-transfer-admin',
        status: :failed,
        primary_addr: networking_ips.fetch(:dns_transfer).fetch(:host_ip).ip_addr,
        serial: 2026051900,
        reason_code: 'webui-failed',
        reason: 'Webui transfer admin fixture',
        message: 'Webui transfer admin fixture failed',
        raw_message: 'webui transfer admin raw message',
        source_cursor: 'webui-transfer-admin-cursor'
      )

      DnsRecordLog
        .where(dns_zone_name: dns_zone_names.values)
        .delete_all
      user_record_log = DnsRecordLog.create!(
        user: user,
        dns_zone: dns_zones.fetch(:user_update),
        dns_zone_name: dns_zones.fetch(:user_update).name,
        change_type: :update_record,
        name: 'www',
        record_type: 'A',
        attr_changes: { content: dns_records.fetch(:user_update).content },
        transaction_chain_id: readonly_chain_id
      )
      admin_record_log = DnsRecordLog.create!(
        user: admin,
        dns_zone: dns_zones.fetch(:admin_log),
        dns_zone_name: dns_zones.fetch(:admin_log).name,
        change_type: :create_record,
        name: 'admin',
        record_type: 'A',
        attr_changes: { content: '198.51.100.40' },
        transaction_chain_id: readonly_chain_id
      )

      SysConfig.find_or_initialize_by(
        category: 'core',
        name: 'snapshot_download_base_url'
      ).tap do |cfg|
        cfg.value = 'https://downloads.example.test'
        cfg.data_type = 'String'
        cfg.min_user_level = 99
        cfg.save! if cfg.changed? || cfg.new_record?
      end
      SnapshotDownload.remove_instance_variable(:@base_url) if SnapshotDownload.instance_variable_defined?(:@base_url)

      storage_snap_seq = 10_000
      make_primary_dip = lambda do |key, owner = user|
        ensure_dataset_in_pool(
          owner,
          storage_primary_pool,
          "webui-storage-#{key}"
        )
      end
      make_primary_with_backup = lambda do |key, owner = user|
        dip = make_primary_dip.call(key, owner)
        ensure_dataset_in_pool(owner, storage_backup_pool, dip.dataset.name)
        dip
      end
      make_snapshot = lambda do |dip, key|
        storage_snap_seq += 1
        ensure_snapshot_fixture(
          dip,
          name: "webui-storage-#{key}",
          label: "Webui Storage #{key}",
          history_id: storage_snap_seq
        )
      end
      make_storage_vps = lambda do |key|
        root_dip = ensure_dataset_in_pool(
          user,
          webui_pool,
          "webui-storage-#{key}-root"
        )
        vps = ensure_storage_vps(
          user,
          root_dip,
          "webui-storage-#{key}",
          node,
          primary_template,
          DnsResolver.first,
          userns_map
        )
        child_dip = ensure_dataset_in_pool(
          user,
          webui_pool,
          "webui-storage-#{key}-child",
          parent: root_dip.dataset
        )
        { vps: vps, root_dip: root_dip, child_dip: child_dip }
      end

      storage_vps = {
        backup: make_storage_vps.call('backup'),
        user_mount_create: make_storage_vps.call('user-mount-create'),
        user_mount_edit: make_storage_vps.call('user-mount-edit'),
        user_mount_toggle: make_storage_vps.call('user-mount-toggle'),
        user_mount_destroy: make_storage_vps.call('user-mount-destroy'),
        admin_mount_create: make_storage_vps.call('admin-mount-create'),
        admin_mount_edit: make_storage_vps.call('admin-mount-edit'),
        admin_mount_toggle: make_storage_vps.call('admin-mount-toggle'),
        admin_mount_destroy: make_storage_vps.call('admin-mount-destroy'),
        admin_expansion_edit: make_storage_vps.call('admin-expansion-edit'),
        admin_expansion_add: make_storage_vps.call('admin-expansion-add'),
        admin_expansion_register: make_storage_vps.call('admin-expansion-register')
      }

      storage_backup_snapshot = make_snapshot.call(
        storage_vps.fetch(:backup).fetch(:root_dip),
        'vps-backup'
      )

      storage_datasets = {
        nas_list: make_primary_with_backup.call('nas-list'),
        user_edit: make_primary_dip.call('user-edit'),
        snapshot_create: make_primary_dip.call('manual-create'),
        restore: make_primary_dip.call('restore'),
        download_create: make_primary_dip.call('download-create'),
        snapshot_destroy: make_primary_dip.call('snapshot-destroy'),
        download_show: make_primary_dip.call('download-show'),
        download_destroy: make_primary_dip.call('download-destroy'),
        export_selector: make_primary_dip.call('export-selector'),
        export_create: make_primary_dip.call('export-create'),
        export_snapshot: make_primary_dip.call('export-snapshot'),
        export_list: make_primary_dip.call('export-list'),
        export_edit: make_primary_dip.call('export-edit'),
        export_enable: make_primary_dip.call('export-enable'),
        export_disable: make_primary_dip.call('export-disable'),
        export_destroy: make_primary_dip.call('export-destroy'),
        export_host_add: make_primary_dip.call('export-host-add'),
        export_host_edit: make_primary_dip.call('export-host-edit'),
        export_host_delete: make_primary_dip.call('export-host-delete'),
        admin_create_parent: make_primary_dip.call('admin-create-parent'),
        admin_edit: make_primary_dip.call('admin-edit'),
        admin_destroy: make_primary_dip.call('admin-destroy'),
        admin_restore: make_primary_dip.call('admin-restore'),
        admin_download_create: make_primary_dip.call('admin-download-create'),
        admin_snapshot_destroy: make_primary_dip.call('admin-snapshot-destroy'),
        admin_expansion_edit: storage_vps.fetch(:admin_expansion_edit).fetch(:root_dip),
        admin_expansion_add: storage_vps.fetch(:admin_expansion_add).fetch(:root_dip),
        admin_expansion_register: storage_vps.fetch(:admin_expansion_register).fetch(:root_dip),
        admin_plan: make_primary_with_backup.call('admin-plan'),
        admin_export_create: make_primary_dip.call('admin-export-create'),
        admin_export_edit: make_primary_dip.call('admin-export-edit'),
        admin_export_enable: make_primary_dip.call('admin-export-enable'),
        admin_export_disable: make_primary_dip.call('admin-export-disable'),
        admin_export_destroy: make_primary_dip.call('admin-export-destroy'),
        admin_export_host_add: make_primary_dip.call('admin-export-host-add'),
        admin_export_host_edit: make_primary_dip.call('admin-export-host-edit'),
        admin_export_host_delete: make_primary_dip.call('admin-export-host-delete')
      }

      storage_snapshots = {
        nas_list: make_snapshot.call(storage_datasets.fetch(:nas_list), 'nas-list'),
        restore: make_snapshot.call(storage_datasets.fetch(:restore), 'restore'),
        download_create: make_snapshot.call(storage_datasets.fetch(:download_create), 'download-create'),
        snapshot_destroy: make_snapshot.call(storage_datasets.fetch(:snapshot_destroy), 'snapshot-destroy'),
        download_show: make_snapshot.call(storage_datasets.fetch(:download_show), 'download-show'),
        download_destroy: make_snapshot.call(storage_datasets.fetch(:download_destroy), 'download-destroy'),
        export_snapshot: make_snapshot.call(storage_datasets.fetch(:export_snapshot), 'export-snapshot'),
        admin_restore: make_snapshot.call(storage_datasets.fetch(:admin_restore), 'admin-restore'),
        admin_download_create: make_snapshot.call(storage_datasets.fetch(:admin_download_create), 'admin-download-create'),
        admin_snapshot_destroy: make_snapshot.call(storage_datasets.fetch(:admin_snapshot_destroy), 'admin-snapshot-destroy')
      }

      storage_downloads = {
        show: ensure_snapshot_download_fixture(
          user,
          storage_snapshots.fetch(:download_show),
          storage_primary_pool,
          'show'
        ),
        destroy: ensure_snapshot_download_fixture(
          user,
          storage_snapshots.fetch(:download_destroy),
          storage_primary_pool,
          'destroy'
        )
      }

      storage_mounts = {
        user_edit: ensure_mount_fixture(
          storage_vps.fetch(:user_mount_edit).fetch(:vps),
          storage_vps.fetch(:user_mount_edit).fetch(:child_dip),
          '/mnt/webui-user-edit'
        ),
        user_toggle: ensure_mount_fixture(
          storage_vps.fetch(:user_mount_toggle).fetch(:vps),
          storage_vps.fetch(:user_mount_toggle).fetch(:child_dip),
          '/mnt/webui-user-toggle'
        ),
        user_destroy: ensure_mount_fixture(
          storage_vps.fetch(:user_mount_destroy).fetch(:vps),
          storage_vps.fetch(:user_mount_destroy).fetch(:child_dip),
          '/mnt/webui-user-destroy'
        ),
        admin_edit: ensure_mount_fixture(
          storage_vps.fetch(:admin_mount_edit).fetch(:vps),
          storage_vps.fetch(:admin_mount_edit).fetch(:child_dip),
          '/mnt/webui-admin-edit'
        ),
        admin_toggle: ensure_mount_fixture(
          storage_vps.fetch(:admin_mount_toggle).fetch(:vps),
          storage_vps.fetch(:admin_mount_toggle).fetch(:child_dip),
          '/mnt/webui-admin-toggle'
        ),
        admin_destroy: ensure_mount_fixture(
          storage_vps.fetch(:admin_mount_destroy).fetch(:vps),
          storage_vps.fetch(:admin_mount_destroy).fetch(:child_dip),
          '/mnt/webui-admin-destroy'
        )
      }

      daily_plan = VpsAdmin::API::DatasetPlans::Registrator.plans.fetch(:daily_backup)
      storage_env_plan = EnvironmentDatasetPlan.find_or_create_by!(
        environment: env,
        dataset_plan: daily_plan.dataset_plan
      ) do |plan|
        plan.user_add = true
        plan.user_remove = true
      end
      storage_env_plan.update!(user_add: true, user_remove: true) unless storage_env_plan.user_add && storage_env_plan.user_remove

      DatasetInPoolPlan
        .where(dataset_in_pool: storage_datasets.fetch(:admin_plan))
        .find_each do |plan|
          storage_datasets.fetch(:admin_plan).del_plan(plan)
        rescue ActiveRecord::RecordNotFound
          plan.destroy!
        end

      storage_expansion = DatasetExpansion.find_or_initialize_by(
        dataset: storage_datasets.fetch(:admin_expansion_edit).dataset
      )
      storage_expansion.assign_attributes(
        vps: storage_vps.fetch(:admin_expansion_edit).fetch(:vps),
        original_refquota: 10_240,
        added_space: 1024,
        max_over_refquota_seconds: 30 * 24 * 60 * 60,
        enable_notifications: true,
        enable_shrink: true,
        stop_vps: false,
        state: :active,
        over_refquota_seconds: 0
      )
      storage_expansion.save! if storage_expansion.changed? || storage_expansion.new_record?
      storage_datasets.fetch(:admin_expansion_edit).dataset.update!(dataset_expansion: storage_expansion)
      DatasetExpansionHistory.find_or_initialize_by(
        dataset_expansion: storage_expansion,
        added_space: 1024
      ).tap do |history|
        history.original_refquota = 10_240
        history.new_refquota = 11_264
        history.admin = admin
        history.save! if history.changed? || history.new_record?
      end

      storage_export_network = ensure_storage_export_network(node.location)
      storage_export_ips = (10..45).map do |i|
        ensure_ip_fixture(
          storage_export_network,
          "198.51.101.#{i}",
          user: user
        )
      end
      export_ip_enum = storage_export_ips.each
      make_export = lambda do |key, enabled: true, host_ip: nil|
        ensure_export_fixture(
          user,
          storage_datasets.fetch(key),
          export_ip_enum.next,
          key,
          enabled: enabled,
          host_ip: host_ip
        )
      end

      storage_exports = {
        list: make_export.call(:export_list),
        edit: make_export.call(:export_edit),
        enable: make_export.call(:export_enable, enabled: false),
        disable: make_export.call(:export_disable, enabled: true),
        destroy: make_export.call(:export_destroy),
        host_add: make_export.call(:export_host_add),
        host_edit: make_export.call(:export_host_edit, host_ip: fixture_assigned_ip),
        host_delete: make_export.call(:export_host_delete, host_ip: fixture_assigned_ip),
        admin_edit: make_export.call(:admin_export_edit),
        admin_enable: make_export.call(:admin_export_enable, enabled: false),
        admin_disable: make_export.call(:admin_export_disable, enabled: true),
        admin_destroy: make_export.call(:admin_export_destroy),
        admin_host_add: make_export.call(:admin_export_host_add),
        admin_host_edit: make_export.call(:admin_export_host_edit, host_ip: fixture_assigned_ip),
        admin_host_delete: make_export.call(:admin_export_host_delete, host_ip: fixture_assigned_ip)
      }

      support_outage_public = ensure_outage_fixture(
        summary: 'Webui Support Public Outage',
        description: 'Deterministic outage visible to users and the public.',
        state: :announced,
        outage_type: :planned_outage,
        impact_type: :network,
        begins_at: Time.now + 3600,
        duration: 45,
        node: node,
        handler: admin,
        vps: support_vps,
        export: storage_exports.fetch(:list).fetch(:export)
      )

      support_outage_admin = ensure_outage_fixture(
        summary: 'Webui Support Admin Outage',
        description: 'Deterministic outage used for admin edit coverage.',
        state: :announced,
        outage_type: :unplanned_outage,
        impact_type: :performance,
        begins_at: Time.now + 7200,
        duration: 30,
        node: node,
        handler: admin,
        vps: support_vps,
        export: storage_exports.fetch(:list).fetch(:export)
      )

      support_outage_staged = ensure_outage_fixture(
        summary: 'Webui Support Staged Outage',
        description: 'Deterministic staged outage used for state changes.',
        state: :staged,
        outage_type: :planned_outage,
        impact_type: :unavailability,
        begins_at: Time.now + 10_800,
        duration: 60,
        node: node,
        handler: admin,
        vps: support_vps
      )

      cleanup_security_advisory_fixtures

      advisory_vulnerable_until = Time.now - 2 * 60 * 60
      advisory_mitigated_since = Time.now - 60 * 60
      advisory_nodes = SecurityAdvisory.advisory_nodes.to_a
      affected_node_statuses = advisory_nodes.to_h do |advisory_node|
        if advisory_node.id == support_vps.node_id
          [
            advisory_node.id,
            {
              state: :mitigated,
              vulnerable_until: advisory_vulnerable_until,
              mitigated_since: advisory_mitigated_since,
              notes: {
                en: 'Mitigated by kernel upgrade',
                cs: 'Ošetřeno aktualizací jádra'
              }
            }
          ]
        else
          [
            advisory_node.id,
            {
              state: :not_affected,
              vulnerable_until: nil,
              mitigated_since: nil,
              notes: {}
            }
          ]
        end
      end
      unknown_node_statuses = advisory_nodes.to_h do |advisory_node|
        [
          advisory_node.id,
          {
            state: :unknown,
            vulnerable_until: nil,
            mitigated_since: nil,
            notes: {}
          }
        ]
      end

      security_advisory_published_affected = ensure_security_advisory_fixture(
        name: 'Webui Security Advisory Affected',
        cves: ['CVE-2099-10001', 'CVE-2099-10002'],
        summary: 'Webui published advisory affecting fixture VPS',
        description: 'Deterministic advisory that affects the support VPS.',
        response: 'The affected node was mitigated in the fixture.',
        node_statuses: affected_node_statuses,
        published_at: Time.now - 4 * 60 * 60,
        publish: true,
        admin: admin
      )

      security_advisory_published_not_affected = ensure_security_advisory_fixture(
        name: 'Webui Security Advisory Not Affected',
        cves: ['CVE-2099-10003'],
        summary: 'Webui published advisory not affecting fixture VPS',
        description: 'Deterministic advisory with all nodes marked not affected.',
        response: 'No user VPS was affected by this fixture advisory.',
        node_statuses: {},
        published_at: Time.now - 3 * 60 * 60,
        publish: true,
        admin: admin
      )

      security_advisory_draft_hidden = ensure_security_advisory_fixture(
        name: 'Webui Security Advisory Draft Hidden',
        cves: ['CVE-2099-10004'],
        summary: 'Webui draft advisory hidden from users',
        description: 'Deterministic draft advisory visible only to admins.',
        response: 'This draft has not been published.',
        node_statuses: unknown_node_statuses,
        published_at: nil,
        publish: false,
        admin: admin
      )

      monitoring_events = {
        user_show: ensure_monitored_event_fixture(
          monitor: :vps_in_rescue_mode,
          object: support_vps,
          user: user,
          value: 'webui support show event'
        ),
        user_ack: ensure_monitored_event_fixture(
          monitor: :vps_zombie_processes,
          object: jumpto_vps,
          user: user,
          value: 'webui support acknowledge event'
        ),
        user_ignore: ensure_monitored_event_fixture(
          monitor: :outgoing_data_flow,
          object: networking_vps.fetch(:list).fetch(:vps),
          user: user,
          value: 'webui support ignore event'
        ),
        admin_ack: ensure_monitored_event_fixture(
          monitor: :vps_zombie_processes,
          object: storage_vps.fetch(:backup).fetch(:vps),
          user: user,
          value: 'webui admin acknowledge event'
        ),
        admin_ignore: ensure_monitored_event_fixture(
          monitor: :outgoing_data_flow,
          object: storage_vps.fetch(:user_mount_create).fetch(:vps),
          user: user,
          value: 'webui admin ignore event'
        )
      }
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

      OomReportRule
        .where(vps: support_vps)
        .where('cgroup_pattern LIKE ?', '/webui-playwright-%')
        .destroy_all

      pools_by_filesystem = Pool
        .where(filesystem: [
          ${builtins.toJSON "tank/ct"},
          ${builtins.toJSON "tank/webui-node1-secondary"},
          ${builtins.toJSON "tank/webui-node2"},
          ${builtins.toJSON "tank/webui-storage-primary"},
          ${builtins.toJSON "tank/webui-storage-backup"}
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
          },
          'selfService' => {
            'knownDevice' => {
              'id' => self_service_known_device.id,
              'ip' => self_service_known_device.client_ip_addr,
              'ptr' => self_service_known_device.client_ip_ptr
            },
            'paymentInstructions' => self_service_payment_instructions,
            'userSession' => {
              'id' => self_service_session.id,
              'label' => self_service_session.label,
              'editedLabel' => "#{self_service_prefix} Session Edited"
            },
            'webauthnCredential' => {
              'id' => self_service_webauthn.id,
              'label' => self_service_webauthn.label,
              'editedLabel' => "#{self_service_prefix} Passkey Edited"
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
        'timeZoneTip' => {
          'set' => {
            'id' => time_zone_tip_set_user.id,
            'username' => time_zone_tip_set_user.login,
            'password' => 'webuiTimeZoneTipSetPassword'
          },
          'dismiss' => {
            'id' => time_zone_tip_dismiss_user.id,
            'username' => time_zone_tip_dismiss_user.login,
            'password' => 'webuiTimeZoneTipDismissPassword'
          },
          'utc' => {
            'id' => time_zone_tip_utc_user.id,
            'username' => time_zone_tip_utc_user.login,
            'password' => 'webuiTimeZoneTipUtcPassword'
          }
        },
        'adminMembers' => {
          'managed' => {
            'id' => admin_managed_user.id,
            'username' => admin_managed_user.login,
            'password' => 'webuiAdminManagedPassword',
            'email' => admin_managed_user.email,
            'monthlyPayment' => 100,
            'environmentConfig' => {
              'id' => EnvironmentUserConfig.find_by!(
                user: admin_managed_user,
                environment: env
              ).id,
              'environmentId' => env.id
            },
            'publicKey' => {
              'id' => admin_managed_public_key.id,
              'label' => admin_managed_public_key.label
            },
            'userSession' => {
              'id' => admin_user_session.id,
              'label' => admin_user_session.label,
              'editedLabel' => "#{admin_member_prefix} Session Edited"
            },
            'resourcePackage' => {
              'id' => admin_resource_package.id,
              'label' => admin_resource_package.label,
              'itemId' => admin_resource_package_item.id
            },
            'incomingPayment' => {
              'id' => admin_incoming_payment.id,
              'transactionId' => admin_incoming_payment.transaction_id,
              'amount' => admin_incoming_payment.amount.to_i,
              'state' => admin_incoming_payment.state
            },
            'userPayment' => {
              'id' => admin_redirect_payment.id,
              'amount' => admin_redirect_payment.amount.to_i
            },
            'approvalRequests' => {
              'approve' => {
                'id' => admin_approval_approve.id,
                'type' => 'change',
                'reason' => admin_approval_approve.change_reason
              },
              'deny' => {
                'id' => admin_approval_deny.id,
                'type' => 'change',
                'reason' => admin_approval_deny.change_reason
              },
              'ignore' => {
                'id' => admin_approval_ignore.id,
                'type' => 'change',
                'reason' => admin_approval_ignore.change_reason
              },
              'hardDeletedDenied' => {
                'id' => hard_deleted_request.id,
                'type' => 'change',
                'reason' => hard_deleted_request.change_reason,
                'userId' => hard_deleted_request.user_id,
                'fullName' => hard_deleted_request.full_name,
                'email' => hard_deleted_request.email,
                'address' => hard_deleted_request.address
              }
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
        'kernelEvidence' => {
          'reportedBootId' => reported_boot.id,
          'reconstructedBootId' => reconstructed_boot.id
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
        'clusterAdmin' => {
          'environment' => {
            'id' => cluster_admin_env.id,
            'label' => cluster_admin_env.label,
            'domain' => cluster_admin_env.domain,
            'description' => cluster_admin_env.description,
            'updatedDescription' => "#{cluster_admin_prefix} Environment updated"
          },
          'locations' => {
            'base' => {
              'id' => cluster_admin_location.id,
              'label' => cluster_admin_location.label,
              'domain' => cluster_admin_location.domain
            },
            'other' => {
              'id' => cluster_admin_other_location.id,
              'label' => cluster_admin_other_location.label,
              'domain' => cluster_admin_other_location.domain
            },
            'create' => {
              'label' => "#{cluster_admin_prefix} Created Location",
              'editedLabel' => "#{cluster_admin_prefix} Created Location Edited",
              'description' => "#{cluster_admin_prefix} Created Location Description",
              'editedDescription' => "#{cluster_admin_prefix} Created Location Updated",
              'domain' => 'cluster-admin-created',
              'editedDomain' => 'cluster-admin-created-b',
              'remoteConsoleServer' => 'http://console.vpsadmin.test'
            }
          },
          'networks' => {
            'networkToLocation' => {
              'id' => cluster_admin_network.id,
              'cidr' => cluster_admin_network.to_s,
              'label' => cluster_admin_network.label
            },
            'locationToNetwork' => {
              'id' => cluster_admin_other_network.id,
              'cidr' => cluster_admin_other_network.to_s,
              'label' => cluster_admin_other_network.label
            },
            'ipAdd' => {
              'id' => cluster_admin_ip_network.id,
              'cidr' => cluster_admin_ip_network.to_s,
              'label' => cluster_admin_ip_network.label,
              'address' => "#{cluster_admin_ip_addr}/32",
              'hostAddress' => cluster_admin_ip_addr
            }
          },
          'dnsResolver' => {
            'label' => "#{cluster_admin_prefix} DNS Resolver",
            'updatedLabel' => "#{cluster_admin_prefix} DNS Resolver Updated",
            'ip' => '198.51.100.53',
            'updatedIp' => '198.51.100.54'
          },
          'resourcePackage' => {
            'label' => "#{cluster_admin_prefix} Package",
            'updatedLabel' => "#{cluster_admin_prefix} Package Updated",
            'resourceId' => ClusterResource.find_by!(name: 'cpu').id,
            'resourceLabel' => ClusterResource.find_by!(name: 'cpu').label
          },
          'osTemplate' => {
            'osFamilyId' => cluster_admin_os_family.id,
            'label' => "#{cluster_admin_prefix} Template",
            'vendor' => 'webui',
            'variant' => 'cluster-admin',
            'arch' => 'x86_64',
            'distribution' => 'webui-cluster',
            'version' => '1'
          },
          'eventLog' => {
            'message' => "#{cluster_admin_prefix} News",
            'updatedMessage' => "#{cluster_admin_prefix} News Updated"
          },
          'helpBox' => {
            'page' => 'cluster',
            'action' => 'webui_cluster_admin',
            'content' => "#{cluster_admin_prefix} Help Content",
            'updatedContent' => "#{cluster_admin_prefix} Help Content Updated"
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
          'pools' => {
            'primary' => {
              'id' => storage_primary_pool.id,
              'filesystem' => storage_primary_pool.filesystem
            },
            'backup' => {
              'id' => storage_backup_pool.id,
              'filesystem' => storage_backup_pool.filesystem
            }
          },
          'dataset' => {
            'id' => fixture_storage_dip.dataset.id,
            'name' => fixture_storage_dip.dataset.name,
            'fullName' => fixture_storage_dip.dataset.full_name
          },
          'datasetInPool' => {
            'id' => fixture_storage_dip.id,
            'poolId' => fixture_storage_dip.pool_id,
            'poolFilesystem' => fixture_storage_dip.pool.filesystem
          },
          'snapshot' => {
            'id' => fixture_snapshot.id,
            'name' => fixture_snapshot.name,
            'label' => fixture_snapshot.label
          },
          'snapshotInPool' => {
            'id' => fixture_snapshot_in_pool.id
          },
          'vps' => storage_vps.transform_values do |vps_fixture|
            vps = vps_fixture.fetch(:vps)
            root_dip = vps_fixture.fetch(:root_dip)
            child_dip = vps_fixture.fetch(:child_dip)

            {
              'id' => vps.id,
              'hostname' => vps.hostname,
              'userNamespaceMapId' => vps.user_namespace_map_id,
              'uidMap' => vps.user_namespace_map.build_map(:uid),
              'gidMap' => vps.user_namespace_map.build_map(:gid),
              'datasetId' => root_dip.dataset.id,
              'datasetFullName' => root_dip.dataset.full_name,
              'datasetInPoolId' => root_dip.id,
              'datasetPoolFilesystem' => root_dip.pool.filesystem,
              'childDatasetId' => child_dip.dataset.id,
              'childDatasetName' => child_dip.dataset.name,
              'childDatasetFullName' => child_dip.dataset.full_name,
              'childDatasetPoolFilesystem' => child_dip.pool.filesystem
            }
          end,
          'datasets' => storage_datasets.transform_values do |dip|
            {
              'id' => dip.dataset.id,
              'name' => dip.dataset.name,
              'fullName' => dip.dataset.full_name,
              'datasetInPoolId' => dip.id,
              'poolId' => dip.pool_id,
              'poolFilesystem' => dip.pool.filesystem
            }
          end,
          'snapshots' => storage_snapshots.merge(
            vps_backup: storage_backup_snapshot
          ).transform_values do |snapshot|
            {
              'id' => snapshot.id,
              'datasetId' => snapshot.dataset_id,
              'name' => snapshot.name,
              'label' => snapshot.label
            }
          end,
          'downloads' => storage_downloads.transform_values do |download|
            {
              'id' => download.id,
              'snapshotId' => download.snapshot_id,
              'fileName' => download.file_name,
              'url' => download.url
            }
          end,
          'mounts' => storage_mounts.transform_values do |mount|
            {
              'id' => mount.id,
              'vpsId' => mount.vps_id,
              'datasetId' => mount.dataset_in_pool.dataset_id,
              'mountpoint' => mount.dst,
              'enabled' => mount.enabled
            }
          end,
          'exports' => storage_exports.transform_values do |export_fixture|
            export = export_fixture.fetch(:export)
            host = export_fixture.fetch(:export_host)

            {
              'id' => export.id,
              'datasetId' => export.dataset.id,
              'datasetName' => export.dataset.name,
              'poolFilesystem' => export.dataset_in_pool.pool.filesystem,
              'path' => export.path,
              'enabled' => export.enabled,
              'hostId' => host&.id
            }
          end,
          'plan' => {
            'environmentDatasetPlanId' => storage_env_plan.id,
            'label' => storage_env_plan.label
          },
          'ipAddresses' => {
            'assignedHost' => {
              'id' => fixture_assigned_ip.id,
              'addr' => fixture_assigned_ip.ip_addr
            }
          }
        },
        'networking' => {
          'network' => {
            'id' => networking_network.id,
            'cidr' => networking_network.to_s,
            'label' => networking_network.label
          },
          'legacyNetwork' => {
            'id' => fixture_network.id,
            'cidr' => fixture_network.to_s,
            'label' => fixture_network.label
          },
          'vps' => networking_vps.transform_values do |vps_fixture|
            vps = vps_fixture.fetch(:vps)
            netif = vps_fixture.fetch(:netif)

            {
              'id' => vps.id,
              'hostname' => vps.hostname,
              'networkInterfaceId' => netif.id,
              'networkInterfaceName' => netif.name
            }
          end,
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
          }.merge(networking_ips.to_h do |key, ip_fixture|
            ip = ip_fixture.fetch(:ip)
            host_ip = ip_fixture.fetch(:host_ip)

            [key, {
              'id' => ip.id,
              'addr' => ip.ip_addr,
              'prefix' => ip.prefix,
              'hostAddressId' => host_ip.id,
              'hostAddress' => host_ip.ip_addr,
              'assignmentId' => networking_assignments[key]&.id
            }]
          end),
          'hostAddresses' => networking_ips.transform_values do |ip_fixture|
            ip = ip_fixture.fetch(:ip)
            host_ip = ip_fixture.fetch(:host_ip)
            netif = ip.network_interface
            vps = netif&.vps

            {
              'id' => host_ip.id,
              'addr' => host_ip.ip_addr,
              'ipAddressId' => ip.id,
              'routedAddress' => ip.ip_addr,
              'assigned' => host_ip.assigned?,
              'vpsId' => vps&.id,
              'networkInterfaceId' => netif&.id
            }
          end,
          'multihost' => {
            'user' => {
              'id' => networking_multihost_user_ip.id,
              'addr' => networking_multihost_user_ip.ip_addr,
              'prefix' => networking_multihost_user_ip.prefix,
              'newHostAddress' => '203.0.113.197'
            },
            'admin' => {
              'id' => networking_multihost_admin_ip.id,
              'addr' => networking_multihost_admin_ip.ip_addr,
              'prefix' => networking_multihost_admin_ip.prefix,
              'newHostAddress' => '203.0.113.201'
            }
          },
          'accounting' => {
            'year' => networking_accounting.year,
            'month' => networking_accounting.month,
            'vpsId' => networking_vps.fetch(:list).fetch(:vps).id,
            'networkInterfaceId' => networking_vps.fetch(:list).fetch(:netif).id,
            'networkInterfaceName' => networking_vps.fetch(:list).fetch(:netif).name
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
          },
          'server' => {
            'id' => dns_server.id,
            'name' => dns_server.name,
            'ipv4' => dns_server.ipv4_addr
          },
          'zones' => dns_zones.transform_values do |zone|
            {
              'id' => zone.id,
              'name' => zone.name,
              'label' => zone.label,
              'source' => zone.zone_source,
              'role' => zone.zone_role,
              'defaultTtl' => zone.default_ttl
            }
          end,
          'records' => dns_records.transform_values do |record|
            {
              'id' => record.id,
              'zoneId' => record.dns_zone_id,
              'name' => record.name,
              'type' => record.record_type,
              'content' => record.content,
              'enabled' => record.enabled
            }
          end,
          'dnssec' => {
            'userKeyId' => 12345,
            'adminKeyId' => 54321
          },
          'serverZones' => {
            'transferLog' => {
              'id' => dns_server_zone_log.id,
              'zoneId' => dns_server_zone_log.dns_zone_id,
              'serverId' => dns_server_zone_log.dns_server_id
            },
            'delete' => {
              'id' => dns_server_zone_delete.id,
              'zoneId' => dns_server_zone_delete.dns_zone_id,
              'serverId' => dns_server_zone_delete.dns_server_id
            }
          },
          'transfers' => {
            'delete' => {
              'id' => dns_transfer_delete.id,
              'zoneId' => dns_transfer_delete.dns_zone_id,
              'hostIpAddressId' => dns_transfer_delete.host_ip_address_id
            },
            'hostIpAddressId' => networking_ips.fetch(:dns_transfer).fetch(:host_ip).id,
            'hostIpAddress' => networking_ips.fetch(:dns_transfer).fetch(:host_ip).ip_addr
          },
          'logs' => {
            'recordUser' => {
              'id' => user_record_log.id,
              'zoneId' => user_record_log.dns_zone_id,
              'zoneName' => user_record_log.dns_zone_name,
              'name' => user_record_log.name
            },
            'recordAdmin' => {
              'id' => admin_record_log.id,
              'zoneId' => admin_record_log.dns_zone_id,
              'zoneName' => admin_record_log.dns_zone_name,
              'name' => admin_record_log.name
            },
            'transferUser' => {
              'id' => user_transfer_log.id,
              'zoneId' => dns_server_zone_log.dns_zone_id,
              'serverZoneId' => user_transfer_log.dns_server_zone_id,
              'reasonCode' => user_transfer_log.reason_code
            },
            'transferAdmin' => {
              'id' => admin_transfer_log.id,
              'zoneId' => dns_server_zone_log.dns_zone_id,
              'serverZoneId' => admin_transfer_log.dns_server_zone_id,
              'reasonCode' => admin_transfer_log.reason_code
            }
          },
          'tsigKeys' => dns_tsig_keys.transform_values do |key|
            {
              'id' => key.id,
              'name' => key.name,
              'algorithm' => key.algorithm,
              'userId' => key.user_id
            }
          end,
          'createNames' => {
            'userPrimary' => 'webui-user-primary-create.example.test',
            'userSecondary' => 'webui-user-secondary-create.example.test',
            'adminPrimary' => 'webui-admin-primary-create.example.test',
            'adminSecondary' => 'webui-admin-secondary-create.example.test',
            'userTsig' => 'webui-user-tsig-create',
            'adminTsig' => 'webui-admin-tsig-create'
          }
        },
        'support' => {
          'vps' => {
            'id' => support_vps.id,
            'hostname' => support_vps.hostname,
            'networkInterfaceId' => support_netif.id,
            'ipAddress' => fixture_assigned_ip.ip_addr,
            'assignmentId' => support_assignment.id
          },
          'mailbox' => {
            'id' => support_mailbox.id,
            'label' => support_mailbox.label
          },
          'incidentReport' => {
            'id' => support_incident.id,
            'subject' => support_incident.subject,
            'codename' => support_incident.codename,
            'text' => support_incident.text,
            'vpsId' => support_vps.id,
            'ipAddress' => support_assignment.ip_addr,
            'assignmentId' => support_assignment.id
          },
          'oomReport' => {
            'id' => oom_report.id,
            'vpsId' => support_vps.id,
            'ruleId' => oom_rule.id,
            'cgroup' => oom_report.cgroup,
            'killedName' => oom_report.killed_name
          },
          'outages' => {
            'public' => {
              'id' => support_outage_public.id,
              'summary' => 'Webui Support Public Outage',
              'vpsId' => support_vps.id,
              'vpsHostname' => support_vps.hostname,
              'exportId' => storage_exports.fetch(:list).fetch(:export).id,
              'exportPath' => storage_exports.fetch(:list).fetch(:export).path
            },
            'admin' => {
              'id' => support_outage_admin.id,
              'summary' => 'Webui Support Admin Outage'
            },
            'staged' => {
              'id' => support_outage_staged.id,
              'summary' => 'Webui Support Staged Outage'
            }
          },
          'monitoring' => monitoring_events.transform_values { |event| {
            'id' => event.id,
            'monitor' => event.monitor_name,
            'label' => event.monitor_name,
            'issue' => event.monitor_name,
            'objectName' => event.class_name,
            'objectId' => event.row_id,
            'state' => event.state,
            'userId' => event.user_id
          } }
        },
        'securityAdvisories' => {
          'nodes' => advisory_nodes.map do |advisory_node|
            {
              'id' => advisory_node.id,
              'name' => advisory_node.name,
              'domainName' => advisory_node.domain_name,
              'type' => advisory_node.role
            }
          end,
          'publishedAffected' => security_advisory_fixture_json(
            security_advisory_published_affected
          ).merge(
            'vpsId' => support_vps.id,
            'vpsHostname' => support_vps.hostname,
            'nodeId' => support_vps.node_id
          ),
          'publishedNotAffected' => security_advisory_fixture_json(
            security_advisory_published_not_affected
          ),
          'draftHidden' => security_advisory_fixture_json(
            security_advisory_draft_hidden
          ),
          'uiCreate' => {
            'cves' => ['CVE-2099-20001', 'CVE-2099-20002'],
            'editedCves' => ['CVE-2099-20001', 'CVE-2099-20003'],
            'name' => 'Webui Browser Advisory Created',
            'editedName' => 'Webui Browser Advisory Edited',
            'publishedAt' => '2026-05-29 12:00',
            'editedPublishedAt' => '2026-05-29 12:30',
            'vulnerableUntil' => '2026-05-29 08:00',
            'mitigatedSince' => '2026-05-29 10:30',
            'nodeNotes' => {
              'en' => 'Mitigated by kernel upgrade',
              'cs' => 'Ošetřeno aktualizací jádra'
            },
            'notAffectedNotes' => {
              'en' => 'Temporarily marked not affected by Playwright',
              'cs' => 'Dočasně označeno testem Playwright jako nedotčené'
            },
            'summary' => 'Webui browser created advisory summary',
            'description' => 'Webui browser created advisory description.',
            'response' => 'Webui browser created advisory response.',
            'editedSummary' => 'Webui browser edited advisory summary',
            'editedDescription' => 'Webui browser edited advisory description.',
            'editedResponse' => 'Webui browser edited advisory response.',
            'updateSummary' => 'Webui browser advisory update summary',
            'updateMessage' => 'Webui browser advisory update message.',
            'editedUpdateSummary' => 'Webui browser advisory edited update',
            'editedUpdateMessage' => 'Webui browser advisory edited message.',
            'outage' => {
              'id' => support_outage_admin.id,
              'summary' => 'Webui Support Admin Outage',
              'typeText' => 'Unplanned outage',
              'impactText' => 'Performance'
            }
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
          'transactionLabel' => readonly_transaction_label,
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
              run_playwright('vps-user-core', 'specs/vps-user-core.spec.cjs', timeout: 2700)
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
              run_playwright('vps-user-ops', 'specs/vps-user-ops.spec.cjs', timeout: 3600)
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

      users-self-service = {
        description = ''
          Run normal-user member profile and self-service browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui user self-service browser flow' do
            it 'passes Playwright user self-service tests' do
              run_playwright('users-self-service', 'specs/users-self-service.spec.cjs')
            end
          end
        '';
      };

      users-admin = {
        description = ''
          Run admin member management browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui admin member management browser flow' do
            it 'passes Playwright admin member management tests' do
              run_playwright('users-admin', 'specs/users-admin.spec.cjs')
            end
          end
        '';
      };

      storage-backup-export = {
        description = ''
          Run storage, backup, dataset, and export browser tests.
        '';
        script = webuiTestScriptCommon + ''
          def prepare_webui_runtime(fixtures)
            prepare_webui_storage_runtime(fixtures.fetch('storage'))
          end

          describe 'webui storage backup export browser flow' do
            it 'passes Playwright storage, backup, dataset, and export tests' do
              run_playwright('storage-backup-export', 'specs/storage-backup-export.spec.cjs')
            end
          end
        '';
      };

      networking-dns = {
        description = ''
          Run networking and DNS browser tests for user and admin roles.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui networking and DNS browser flow' do
            it 'passes Playwright networking and DNS tests' do
              run_playwright('networking-dns', 'specs/networking.spec.cjs', 'specs/dns.spec.cjs')
            end
          end
        '';
      };

      support-pages = {
        description = ''
          Run support, outage, OOM report, incident, and monitoring browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui support and status browser flow' do
            it 'passes Playwright support and status tests' do
              run_playwright('support-pages', 'specs/support-pages.spec.cjs')
            end
          end
        '';
      };

      security-advisories = {
        description = ''
          Run security advisory browser tests for public, user, and admin flows.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui security advisory browser flow' do
            it 'passes Playwright security advisory tests' do
              run_playwright('security-advisories', 'specs/security-advisories.spec.cjs')
            end
          end
        '';
      };

      misc-pages = {
        description = ''
          Run miscellaneous webui page browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui miscellaneous page browser flow' do
            it 'passes Playwright miscellaneous page tests' do
              run_playwright('misc-pages', 'specs/misc-pages.spec.cjs')
            end
          end
        '';
      };

      admin-cluster = {
        description = ''
          Run admin cluster management browser tests.
        '';
        script = webuiTestScriptCommon + ''
          describe 'webui admin cluster browser flow' do
            it 'passes Playwright admin cluster tests' do
              run_playwright('admin-cluster', 'specs/admin-cluster.spec.cjs')
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
