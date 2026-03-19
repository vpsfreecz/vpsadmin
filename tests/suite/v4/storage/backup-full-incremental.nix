import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.node;
  in
  {
    name = "storage-backup-full-incremental";

    description = ''
      Create a same-node primary+backup setup, run an initial backup plus two
      incremental backups, and verify source rotation preserves the latest
      shared snapshot needed for future incremental transfer.
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

      def head_branch_row(services, dip_id)
        services.mysql_json_rows(sql: <<~SQL).first
          SELECT JSON_OBJECT(
            'tree_id', t.id,
            'tree_index', t.`index`,
            'branch_id', b.id,
            'branch_name', b.name,
            'branch_index', b.`index`
          )
          FROM dataset_trees t
          INNER JOIN branches b ON b.dataset_tree_id = t.id
          WHERE t.dataset_in_pool_id = #{Integer(dip_id)} AND t.head = 1 AND b.head = 1
          LIMIT 1
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

      def branch_dataset_path(pool_fs, dataset_full_name, head_branch)
        [
          pool_fs,
          dataset_full_name,
          "tree.#{head_branch.fetch('tree_index')}",
          "branch-#{head_branch.fetch('branch_name')}.#{head_branch.fetch('branch_index')}"
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

      describe 'full and incremental backup', order: :defined do
        it 'creates primary and backup pools' do
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
        end

        it 'creates a VPS and the matching backup DatasetInPool' do
          _, output = services.vpsadminctl.succeeds(
            args: %w[vps new],
            parameters: {
              user: admin_user_id,
              node: node_id,
              os_template: 1,
              hostname: 'storage-backup',
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
          @primary_dataset_path = "#{primary_pool_fs}/#{@dataset_full_name}"

          wait_until_block_succeeds(name: 'primary dataset exists') do
            node.zfs_exists?(@primary_dataset_path, type: 'filesystem', timeout: 30)
          end

          wait_until_block_succeeds(name: 'backup DatasetInPool available') do
            @backup_dataset_info = dataset_in_pool_info(
              services,
              dataset_id: @dataset_id,
              pool_id: @backup_pool_id
            )
            !@backup_dataset_info.nil?
          end

          @dst_dip_id = @backup_dataset_info.fetch('dataset_in_pool_id')
          @backup_dataset_path = "#{backup_pool_fs}/#{@dataset_full_name}"

          wait_until_block_succeeds(name: 'backup dataset exists') do
            node.zfs_exists?(@backup_dataset_path, type: 'filesystem', timeout: 30)
          end
        end

        it 'backs up the first snapshot into the first tree and head branch' do
          @snap1 = create_snapshot(services, dataset_id: @dataset_id, dip_id: @src_dip_id, label: 'backup-full-1')
          fire_backup(services, admin_user_id: admin_user_id, src_dip_id: @src_dip_id, dst_dip_id: @dst_dip_id)

          services.wait_for_branch_count(@dst_dip_id, count: 1)
          @head_branch = head_branch_row(services, @dst_dip_id)
          @head_branch_dataset_path = branch_dataset_path(backup_pool_fs, @dataset_full_name, @head_branch)

          expect(services.mysql_scalar(sql: "SELECT COUNT(*) FROM dataset_trees WHERE dataset_in_pool_id = #{@dst_dip_id}")).to eq('1')
          expect(snapshot_rows_for_dip(services, @dst_dip_id).map { |row| row.fetch('name') }).to include(@snap1.fetch('name'))
          expect(node.zfs_exists?("#{@head_branch_dataset_path}@#{@snap1.fetch('name')}", type: 'snapshot', timeout: 30)).to be(true)
        end

        it 'reuses the same tree and branch for the next incremental backup' do
          @snap2 = create_snapshot(services, dataset_id: @dataset_id, dip_id: @src_dip_id, label: 'backup-full-2')
          fire_backup(services, admin_user_id: admin_user_id, src_dip_id: @src_dip_id, dst_dip_id: @dst_dip_id)

          head_branch = head_branch_row(services, @dst_dip_id)

          expect(services.mysql_scalar(sql: "SELECT COUNT(*) FROM dataset_trees WHERE dataset_in_pool_id = #{@dst_dip_id}")).to eq('1')
          expect(head_branch.fetch('branch_id')).to eq(@head_branch.fetch('branch_id'))
          expect(snapshot_rows_for_dip(services, @dst_dip_id).map { |row| row.fetch('name') }).to include(
            @snap1.fetch('name'),
            @snap2.fetch('name')
          )
        end

        it 'keeps only the latest shared source snapshot after the previous backup rotation' do
          source_snapshots = snapshot_rows_for_dip(services, @src_dip_id).map { |row| row.fetch('name') }

          expect(source_snapshots).not_to include(@snap1.fetch('name'))
          expect(source_snapshots).to include(@snap2.fetch('name'))
        end

        it 'keeps using the same backup tree and branch after rotation for the third backup' do
          @snap3 = create_snapshot(services, dataset_id: @dataset_id, dip_id: @src_dip_id, label: 'backup-full-3')
          fire_backup(services, admin_user_id: admin_user_id, src_dip_id: @src_dip_id, dst_dip_id: @dst_dip_id)

          head_branch = head_branch_row(services, @dst_dip_id)
          backup_snapshot_names = snapshot_rows_for_dip(services, @dst_dip_id).map { |row| row.fetch('name') }

          expect(services.mysql_scalar(sql: "SELECT COUNT(*) FROM dataset_trees WHERE dataset_in_pool_id = #{@dst_dip_id}")).to eq('1')
          expect(head_branch.fetch('branch_id')).to eq(@head_branch.fetch('branch_id'))
          expect(backup_snapshot_names).to include(@snap2.fetch('name'), @snap3.fetch('name'))
          expect(node.zfs_exists?("#{branch_dataset_path(backup_pool_fs, @dataset_full_name, head_branch)}@#{@snap3.fetch('name')}", type: 'snapshot', timeout: 30)).to be(true)
        end
      end
    '';
  }
)
