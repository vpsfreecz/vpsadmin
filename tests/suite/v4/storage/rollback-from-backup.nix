import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.node;
  in
  {
    name = "storage-rollback-from-backup";

    description = ''
      Back up multiple snapshots of a VPS root dataset, roll back to an older
      snapshot from backup, verify backup branching metadata, then confirm later
      backups continue on the new head branch.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = ''
      require 'json'

      admin_user_id = ${toString adminUser.id}
      node_id = ${toString nodeSeed.id}
      primary_pool_fs = 'tank/ct'
      backup_pool_fs = 'tank/backup'

      def wait_for_running_nodectld(node)
        node.wait_for_service('nodectld')
        wait_until_block_succeeds(name: 'nodectld running') do
          _, output = node.succeeds('nodectl status', timeout: 180)
          expect(output).to include('State: running')
          true
        end
      end

      def wait_for_pool_online(services, pool_id)
        wait_until_block_succeeds(name: "pool #{pool_id} online") do
          _, output = services.vpsadminctl.succeeds(args: ['pool', 'show', pool_id.to_s])
          output.fetch('pool').fetch('state') == 'online'
        end
      end

      def api_session_prelude(admin_user_id)
        <<~RUBY
          user = User.find(#{admin_user_id})
          User.current = user
          UserSession.current = UserSession.create!(
            user: user,
            auth_type: 'basic',
            api_ip_addr: '127.0.0.1',
            client_version: 'storage-integration'
          )
        RUBY
      end

      def dataset_info(services, vps_id)
        services.mysql_json_rows(sql: <<~SQL).first
          SELECT JSON_OBJECT(
            'dataset_id', d.id,
            'dataset_in_pool_id', dip.id,
            'dataset_full_name', d.full_name
          )
          FROM vpses v
          INNER JOIN dataset_in_pools dip ON dip.id = v.dataset_in_pool_id
          INNER JOIN datasets d ON d.id = dip.dataset_id
          WHERE v.id = #{Integer(vps_id)}
        SQL
      end

      def snapshot_rows_for_dip(services, dip_id)
        services.mysql_json_rows(sql: <<~SQL)
          SELECT JSON_OBJECT('id', s.id, 'name', s.name)
          FROM snapshot_in_pools sip
          INNER JOIN snapshots s ON s.id = sip.snapshot_id
          WHERE sip.dataset_in_pool_id = #{Integer(dip_id)}
          ORDER BY s.id
        SQL
      end

      def branch_rows_for_dip(services, dip_id)
        services.mysql_json_rows(sql: <<~SQL)
          SELECT JSON_OBJECT(
            'id', b.id,
            'name', b.name,
            'index', b.`index`,
            'head', b.head,
            'tree_id', t.id,
            'tree_index', t.`index`
          )
          FROM branches b
          INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
          WHERE t.dataset_in_pool_id = #{Integer(dip_id)}
          ORDER BY b.id
        SQL
      end

      def branch_entries_for_dip(services, dip_id)
        services.mysql_json_rows(sql: <<~SQL)
          SELECT JSON_OBJECT(
            'entry_id', e.id,
            'parent_entry_id', e.snapshot_in_pool_in_branch_id,
            'branch_id', b.id,
            'branch_name', b.name,
            'branch_index', b.`index`,
            'tree_index', t.`index`,
            'snapshot_id', s.id,
            'snapshot_name', s.name,
            'reference_count', sip.reference_count
          )
          FROM snapshot_in_pool_in_branches e
          INNER JOIN branches b ON b.id = e.branch_id
          INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
          INNER JOIN snapshot_in_pools sip ON sip.id = e.snapshot_in_pool_id
          INNER JOIN snapshots s ON s.id = sip.snapshot_id
          WHERE t.dataset_in_pool_id = #{Integer(dip_id)}
          ORDER BY s.id, e.id
        SQL
      end

      def dataset_in_pool_info(services, dataset_id:, pool_id:)
        services.mysql_json_rows(sql: <<~SQL).first
          SELECT JSON_OBJECT('dataset_in_pool_id', dip.id)
          FROM dataset_in_pools dip
          WHERE dip.dataset_id = #{Integer(dataset_id)} AND dip.pool_id = #{Integer(pool_id)}
          LIMIT 1
        SQL
      end

      def create_snapshot(services, dataset_id:, dip_id:, label:)
        _, output = services.vpsadminctl.succeeds(
          args: ['dataset.snapshot', 'create', dataset_id.to_s],
          parameters: { label: label }
        )

        snapshot = output.fetch('snapshot')
        services.wait_for_snapshot_in_pool(dip_id, snapshot.fetch('id'))
        snapshot.merge(
          snapshot_rows_for_dip(services, dip_id).find { |row| row.fetch('id') == snapshot.fetch('id') }
        )
      end

      def fire_backup(services, admin_user_id:, src_dip_id:, dst_dip_id:)
        response = services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          src = DatasetInPool.find(#{src_dip_id})
          dst = DatasetInPool.find(#{dst_dip_id})
          chain, = TransactionChains::Dataset::Backup.fire(src, dst)

          puts JSON.dump(chain_id: chain.id)
        RUBY

        services.wait_for_chain_state(response.fetch('chain_id'), state: :done)
        response
      end

      def rollback_dataset_to_snapshot(services, dataset_id:, snapshot_id:)
        _, output = services.vpsadminctl.succeeds(
          args: ['dataset.snapshot', 'rollback', dataset_id.to_s, snapshot_id.to_s]
        )

        {
          'chain_id' => output.dig('_meta', 'action_state_id') || output.dig('response', '_meta', 'action_state_id'),
          'output' => output
        }
      end

      def branch_dataset_path(pool_fs, dataset_full_name, branch_row)
        [
          pool_fs,
          dataset_full_name,
          "tree.#{branch_row.fetch('tree_index')}",
          "branch-#{branch_row.fetch('name')}.#{branch_row.fetch('index')}"
        ].join('/')
      end

      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        node.succeeds('nodectl set config vpsadmin.queues.zfs_send.start_delay=0')
        node.succeeds('nodectl set config vpsadmin.queues.zfs_recv.start_delay=0')
        node.succeeds('nodectl queue resume all')
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'rollback from backup', order: :defined do
        it 'creates primary and backup pools and a VPS with a backup DatasetInPool' do
          _, output = services.vpsadminctl.succeeds(
            args: %w[pool create],
            parameters: {
              node: node_id,
              label: 'primary',
              filesystem: primary_pool_fs,
              role: 'hypervisor',
              is_open: true,
              max_datasets: 100,
              refquota_check: true
            }
          )
          @primary_pool_id = output.fetch('pool').fetch('id')

          _, output = services.vpsadminctl.succeeds(
            args: %w[pool create],
            parameters: {
              node: node_id,
              label: 'backup',
              filesystem: backup_pool_fs,
              role: 'backup',
              is_open: true,
              max_datasets: 100,
              refquota_check: true
            }
          )
          @backup_pool_id = output.fetch('pool').fetch('id')

          wait_for_pool_online(services, @primary_pool_id)
          wait_for_pool_online(services, @backup_pool_id)

          _, output = services.vpsadminctl.succeeds(
            args: %w[vps new],
            parameters: {
              user: admin_user_id,
              node: node_id,
              os_template: 1,
              hostname: 'storage-restore',
              cpu: 1,
              memory: 1024,
              swap: 0,
              diskspace: 10240,
              ipv4: 0,
              ipv4_private: 0,
              ipv6: 0
            }
          )
          @vps_id = output.fetch('vps').fetch('id')

          wait_until_block_succeeds(name: 'dataset info available') do
            @dataset_info = dataset_info(services, @vps_id)
            !@dataset_info.nil?
          end

          @dataset_id = @dataset_info.fetch('dataset_id')
          @src_dip_id = @dataset_info.fetch('dataset_in_pool_id')
          @dataset_full_name = @dataset_info.fetch('dataset_full_name')

          wait_until_block_succeeds(name: 'backup DatasetInPool available') do
            @backup_dataset_info = dataset_in_pool_info(
              services,
              dataset_id: @dataset_id,
              pool_id: @backup_pool_id
            )
            !@backup_dataset_info.nil?
          end

          @dst_dip_id = @backup_dataset_info.fetch('dataset_in_pool_id')
        end

        it 'creates three backups and then rolls back to the middle snapshot' do
          @snapshots = []

          3.times do |i|
            snapshot = create_snapshot(
              services,
              dataset_id: @dataset_id,
              dip_id: @src_dip_id,
              label: "rollback-backup-#{i + 1}"
            )
            @snapshots << snapshot
            fire_backup(services, admin_user_id: admin_user_id, src_dip_id: @src_dip_id, dst_dip_id: @dst_dip_id)
          end

          @history_before = services.mysql_scalar(
            sql: "SELECT current_history_id FROM datasets WHERE id = #{@dataset_id}"
          ).to_i

          rollback = rollback_dataset_to_snapshot(
            services,
            dataset_id: @dataset_id,
            snapshot_id: @snapshots[1].fetch('id')
          )

          services.wait_for_chain_state(rollback.fetch('chain_id'), state: :done)
          services.wait_for_branch_count(@dst_dip_id, count: 2)

          wait_until_block_succeeds(name: 'VPS running after restore') do
            _, output = services.vpsadminctl.succeeds(args: ['vps', 'show', @vps_id.to_s])
            output.fetch('vps').fetch('is_running')
          end
        end

        it 'creates a new head branch and records restore metadata' do
          branches = branch_rows_for_dip(services, @dst_dip_id)
          entries = branch_entries_for_dip(services, @dst_dip_id)
          new_head = branches.find { |row| row.fetch('head') == 1 }
          old_branch = branches.find { |row| row.fetch('head') == 0 }
          s2_entry = entries.find { |row| row.fetch('snapshot_name') == @snapshots[1].fetch('name') }
          s3_entry = entries.find { |row| row.fetch('snapshot_name') == @snapshots[2].fetch('name') }

          expect(branches.count).to eq(2)
          expect(new_head.fetch('name')).to eq(@snapshots[1].fetch('name'))
          expect(old_branch.fetch('head')).to eq(0)
          expect(s3_entry.fetch('parent_entry_id')).to eq(s2_entry.fetch('entry_id'))
          expect(s2_entry.fetch('reference_count')).to be >= 1
          expect(
            services.mysql_scalar(sql: "SELECT current_history_id FROM datasets WHERE id = #{@dataset_id}").to_i
          ).to eq(@history_before + 1)
          expect(
            services.mysql_scalar(
              sql: <<~SQL
                SELECT COUNT(*)
                FROM object_histories
                WHERE tracked_object_type = 'Vps' AND tracked_object_id = #{@vps_id} AND event_type = 'restore'
              SQL
            )
          ).to eq('1')

          branches.each do |branch|
            expect(
              node.zfs_exists?(branch_dataset_path(backup_pool_fs, @dataset_full_name, branch), type: 'filesystem', timeout: 30)
            ).to be(true)
          end

          @head_branch_id = new_head.fetch('id')
        end

        it 'continues future backups on the new head branch' do
          @snap4 = create_snapshot(
            services,
            dataset_id: @dataset_id,
            dip_id: @src_dip_id,
            label: 'rollback-backup-4'
          )
          fire_backup(services, admin_user_id: admin_user_id, src_dip_id: @src_dip_id, dst_dip_id: @dst_dip_id)

          branches = branch_rows_for_dip(services, @dst_dip_id)
          entries = branch_entries_for_dip(services, @dst_dip_id)
          current_head = branches.find { |row| row.fetch('head') == 1 }
          s4_entry = entries.find { |row| row.fetch('snapshot_name') == @snap4.fetch('name') }

          expect(current_head.fetch('id')).to eq(@head_branch_id)
          expect(branches.count).to eq(2)
          expect(s4_entry.fetch('branch_id')).to eq(@head_branch_id)
        end
      end
    '';
  }
)
