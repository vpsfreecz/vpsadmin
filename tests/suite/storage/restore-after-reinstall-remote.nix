import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-2-node.nix;
    node1Seed = clusterSeed.nodes.node1;
    node2Seed = clusterSeed.nodes.node2;
    common = import ./remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = node1Seed.id;
      node2Id = node2Seed.id;
      manageCluster = false;
    };
    # Persist only this scenario's delay policy across an actual daemon restart.
    queueModule = {
      vpsadmin.nodectld.settings.vpsadmin.queues = {
        zfs_send.start_delay = 0;
        zfs_recv.start_delay = 0;
      };
    };
  in
  {
    name = "storage-restore-after-reinstall-remote";

    description = ''
      Create remote backups on a second node, reinstall the VPS to drop primary
      snapshot history, restore from a snapshot that exists only on backup, and
      verify later backups remain incrementally usable.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../machines/cluster/2-node.nix (
      args
      // {
        extraModules = pkgs.lib.recursiveUpdate (args.extraModules or { }) {
          nodes.node1 = queueModule;
          nodes.node2 = queueModule;
        };
      }
    );

    testScript = common + ''
      RESTORE_PROOF_PATH = '/root/vpsadmin-remote-restore-proof.txt'
      RESTORE_PROOF_RELATIVE_PATH = 'private/root/vpsadmin-remote-restore-proof.txt'

      def daemon_identity(node, timeout: 30)
        _, status = node.succeeds('sv status nodectld', timeout: timeout)
        match = status.match(/\(pid (\d+)\)/)
        expect(match).not_to be_nil
        wrapper_pid = Integer(match.captures.fetch(0), 10)
        _, children = node.succeeds("cat /proc/#{wrapper_pid}/task/#{wrapper_pid}/children", timeout: timeout)
        pids = children.split.map { |pid| Integer(pid, 10) }
        expect(pids.length).to eq(1)
        _, stat = node.succeeds("cat /proc/#{pids.first}/stat", timeout: timeout)
        # Fields after comm begin with state (field 3); starttime is field 22.
        fields = stat.match(/\A\d+ \(.*\) (.*)\z/m).captures.fetch(0).split
        [pids.first, Integer(fields.fetch(19), 10)]
      end

      def restart_with_persistent_transfer_delays(node)
        before = daemon_identity(node)
        node.succeeds('nodectl restart', timeout: 180)
        wait_until_block_succeeds(name: "new running nodectld on #{node.name}", timeout: 180) do
          expect(daemon_identity(node)).not_to eq(before)
          node.succeeds('sv check nodectld', timeout: 30)
          node.succeeds('test -S /run/nodectl/nodectld.sock', timeout: 30)
          _, status = node.succeeds('nodectl status', timeout: 30)
          expect(status).to include('State: running')
          true
        end
        %w[zfs_send zfs_recv].each do |queue|
          _, scalar = node.succeeds(
            "nodectl get --parsable config vpsadmin.queues.#{queue}.start_delay",
            timeout: 30
          )
          expect(JSON.parse(scalar)).to eq(0)
        end
      end

      def write_restore_payload(content)
        write_vps_migration_proof(node1, vps_id: @setup.fetch('vps_id'), path: RESTORE_PROOF_PATH, content: content)
      end

      def expect_backup_payload(snapshot, content)
        rows = branch_entries_for_dip(services, @setup.fetch('dst_dip_id')).select do |row|
          row.fetch('snapshot_id') == snapshot.fetch('id')
        end
        expect(rows.length).to eq(1)
        fs = branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), rows.first)
        expect_vps_migration_proof_on_dataset(
          node2,
          dataset_path: fs,
          relative_path: ".zfs/snapshot/#{snapshot.fetch('name')}/#{RESTORE_PROOF_RELATIVE_PATH}",
          content: content
        )
      end

      def receive_history_count(node, filesystem)
        _, output = node.succeeds(
          "zpool history tank | grep -F #{Shellwords.escape(filesystem)} | grep -E 'zfs (recv|receive) ' | wc -l",
          timeout: 30
        )
        Integer(output.strip, 10)
      end

      def transfer_evidence(chain_id)
        # Project only transfer evidence, never signed envelopes, addresses or keys.
        rows = services.mariadb_json_rows(sql: <<~SQL)
          SELECT JSON_OBJECT(
            'id', id, 'handle', handle, 'node_id', node_id, 'done', done, 'status', status,
            'snapshots', JSON_EXTRACT(input, '$.input.snapshots'),
            'result', JSON_UNQUOTE(JSON_EXTRACT(output, '$.execute.status'))
          )
          FROM transactions
          WHERE transaction_chain_id = #{Integer(chain_id)}
            AND handle IN (5220, 5221)
          ORDER BY id LIMIT 4
        SQL
        rows.each do |row|
          snapshots = row.fetch('snapshots')
          row['snapshots'] = JSON.parse(snapshots) if snapshots.is_a?(String)
        end
        rows
      end

      def restore_phase(stage)
        @restore_stage = stage
        yield
      rescue StandardError, RSpec::Expectations::ExpectationNotMetError
        begin
          restore_diagnostics
        # Even a secondary signal must not replace the already pending test failure.
        rescue Exception # rubocop:disable Lint/RescueException
          nil
        end
        raise
      end

      def restore_diagnostics
        warn JSON.dump(stage: @restore_stage)
        ids = [@reinstall_chain_id, @restore_chain_id, @snap1&.fetch('chain_id'),
               @snap2&.fetch('chain_id'), @snap3&.fetch('chain_id')].compact
        if @setup
          # A timed-out CLI may not have returned its new chain ID yet.
          related = services.mariadb_json_rows(timeout: 10, sql: <<~SQL)
            SELECT JSON_OBJECT('chain_id', transaction_chain_id)
            FROM transactions
            WHERE node_id IN (#{Integer(node1_id)}, #{Integer(node2_id)})
              AND handle IN (5220, 5221, 5222)
              AND JSON_UNQUOTE(JSON_EXTRACT(input, '$.input.dataset_name')) = #{@setup.fetch('dataset_full_name').inspect}
            ORDER BY id DESC LIMIT 8
          SQL
          ids.concat(related.map { |row| Integer(row.fetch('chain_id')) })
        end
        ids = ids.uniq.last(8)
        unless ids.empty?
          rows = services.mariadb_json_rows(timeout: 10, sql: <<~SQL)
            SELECT JSON_OBJECT(
              'chain', t.transaction_chain_id, 'chain_state', c.state,
              'id', t.id, 'node', t.node_id, 'handle', t.handle,
              'queue', t.queue, 'done', t.done, 'status', t.status,
              'started_at', t.started_at, 'finished_at', t.finished_at
            )
            FROM transactions t LEFT JOIN transaction_chains c ON c.id = t.transaction_chain_id
            WHERE t.transaction_chain_id IN (#{ids.join(',')})
            ORDER BY t.done = 0 DESC, t.id DESC LIMIT 32
          SQL
          warn JSON.dump(stage: @restore_stage, transactions: rows)
        end
        [node1, node2].each do |node|
          begin
            identity = daemon_identity(node, timeout: 10)
            _, workers = node.succeeds(
              "nodectl status --workers --parsable --no-header | awk '$1 ~ /^zfs_(send|recv)$/ {print $1,$2,$3,$4,$5,$6,$7}' | head -n 8",
              timeout: 10
            )
            _, children = node.succeeds('ps -C mbuffer,zfs -o pid=,ppid=,stat=,comm= | head -n 16', timeout: 10)
            _, errors = node.succeeds(
              "tail -n 400 /var/log/messages | grep -Eo '(Bunny|NodeCtld::RpcClient|Timeout)::[A-Za-z:]+' | tail -n 16",
              timeout: 10
            )
            delays = %w[zfs_send zfs_recv].map do |queue|
              _, scalar = node.succeeds("nodectl get --parsable config vpsadmin.queues.#{queue}.start_delay", timeout: 10)
              JSON.parse(scalar)
            end
            _, reservations = node.succeeds('nodectl status --reservations | head -n 16', timeout: 10)
            warn JSON.dump(node: node.name, identity: identity, delays: delays,
                           workers: workers, reservations: reservations, children: children, error_classes: errors)
          rescue StandardError, RSpec::Expectations::ExpectationNotMetError
            warn JSON.dump(node: node.name, diagnostics_unavailable: true)
          end
        end
        _, broker_errors = services.succeeds(
          "journalctl -u rabbitmq.service --no-pager -n 200 | grep -Eoi '(error|timeout|exception|closed)' | tail -n 16",
          timeout: 10
        )
        warn JSON.dump(broker_error_categories: broker_errors)
      end

      describe 'restore after reinstall from remote backup', order: :defined do
        before(:suite) do
          services.start
          node1.start
          node2.start
          services.wait_for_vpsadmin_api
          [node1, node2].each do |node|
            wait_for_running_nodectld(node)
            restart_with_persistent_transfer_delays(node)
          end
          wait_for_node_ready(services, node1_id)
          wait_for_node_ready(services, node2_id)
          services.unlock_transaction_signing_key(passphrase: 'test')
        end

        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          restore_phase(1) do
            @setup = create_remote_backup_vps(
              services,
              primary_node: node1,
              backup_node: node2,
              admin_user_id: admin_user_id,
              primary_node_id: node1_id,
              backup_node_id: node2_id,
              hostname: 'storage-remote-reinstall',
              primary_pool_fs: primary_pool_fs,
              backup_pool_fs: backup_pool_fs
            )
          end
        end

        it 'creates remote backup history and reinstalls the VPS' do
          restore_phase(2) do
            write_restore_payload('remote restore A')
            @snap1 = create_and_backup_snapshot(
              services,
              admin_user_id: admin_user_id,
              dataset_id: @setup.fetch('dataset_id'),
              src_dip_id: @setup.fetch('src_dip_id'),
              dst_dip_id: @setup.fetch('dst_dip_id'),
              label: 'remote-reinstall-1'
            )
            expect_backup_payload(@snap1, 'remote restore A')
            write_restore_payload('remote restore B')
            @snap2 = create_and_backup_snapshot(
              services,
              admin_user_id: admin_user_id,
              dataset_id: @setup.fetch('dataset_id'),
              src_dip_id: @setup.fetch('src_dip_id'),
              dst_dip_id: @setup.fetch('dst_dip_id'),
              label: 'remote-reinstall-2'
            )
            expect_backup_payload(@snap1, 'remote restore A')
            expect_backup_payload(@snap2, 'remote restore B')

            @history_before_reinstall = current_history_id(services, @setup.fetch('dataset_id'))

            reinstall = reinstall_vps(
              services,
              admin_user_id: admin_user_id,
              vps_id: @setup.fetch('vps_id')
            )
            @reinstall_chain_id = reinstall.fetch('chain_id')

            services.wait_for_chain_state(@reinstall_chain_id, state: :done)
            wait_for_vps_running(services, @setup.fetch('vps_id'))
            wait_for_vps_exec(node1, vps_id: @setup.fetch('vps_id'))
            vps_exec(node1, vps_id: @setup.fetch('vps_id'), command: "test ! -e #{RESTORE_PROOF_PATH}")

            wait_until_block_succeeds(name: 'local snapshots removed after reinstall') do
              snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).empty?
            end

            expect(current_history_id(services, @setup.fetch('dataset_id'))).to eq(@history_before_reinstall + 1)
            expect_backup_payload(@snap1, 'remote restore A')
            expect_backup_payload(@snap2, 'remote restore B')
          end
        end

        it 'restores from backup-only history over the remote send/recv rollback path' do
          restore_phase(3) do
            restore = rollback_dataset_to_snapshot(
              services,
              dataset_id: @setup.fetch('dataset_id'),
              snapshot_id: @snap2.fetch('id')
            )
            @restore_chain_id = restore.fetch('chain_id')

            services.wait_for_chain_state(@restore_chain_id, state: :done)
            wait_for_vps_running(services, @setup.fetch('vps_id'))
            wait_for_chain_locks_released(services, @restore_chain_id)
            expect_vps_migration_proof(node1, vps_id: @setup.fetch('vps_id'), path: RESTORE_PROOF_PATH, content: 'remote restore B')

            restore_handles = chain_transactions(services, @restore_chain_id).map { |row| row.fetch('handle') }
            primary_snapshot_names = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).map { |row| row.fetch('name') }

            expect(restore_handles).to include(
              tx_types(services).fetch('prepare_rollback'),
              tx_types(services).fetch('send'),
              tx_types(services).fetch('recv'),
              tx_types(services).fetch('recv_check'),
              tx_types(services).fetch('apply_rollback')
            )
            expect(restore_handles).not_to include(tx_types(services).fetch('local_send'))
            expect(primary_snapshot_names).to include(@snap2.fetch('name'))
            expect(head_tree_row(services, @setup.fetch('dst_dip_id'))).not_to be_nil
            expect(head_branch_row(services, @setup.fetch('dst_dip_id'))).not_to be_nil
            expect_backup_payload(@snap1, 'remote restore A')
            expect_backup_payload(@snap2, 'remote restore B')
          end
        end

        it 'keeps the restored backup history incrementally usable for future backups' do
          restore_phase(4) do
            restored_head = head_branch_row(services, @setup.fetch('dst_dip_id'))
            restored_fs = branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), restored_head)
            before_receives = receive_history_count(node2, restored_fs)
            write_restore_payload('remote restore C')
            @snap3 = create_and_backup_snapshot(
              services,
              admin_user_id: admin_user_id,
              dataset_id: @setup.fetch('dataset_id'),
              src_dip_id: @setup.fetch('src_dip_id'),
              dst_dip_id: @setup.fetch('dst_dip_id'),
              label: 'remote-reinstall-3'
            )

            services.wait_for_tree_count(@setup.fetch('dst_dip_id'), count: 1)

            branches = branch_rows_for_dip(services, @setup.fetch('dst_dip_id'))
            entries = branch_entries_for_dip(services, @setup.fetch('dst_dip_id'))
            head_branch = branches.find { |row| row.fetch('head') == 1 }
            s3_entry = entries.find { |row| row.fetch('snapshot_name') == @snap3.fetch('name') }
            backup_handles = chain_transactions(services, @snap3.fetch('chain_id')).map { |row| row.fetch('handle') }

            expect(branches.count).to eq(1)
            expect(head_branch.fetch('id')).to eq(restored_head.fetch('branch_id'))
            expect(s3_entry.fetch('branch_id')).to eq(head_branch.fetch('id'))
            expect(backup_handles).to include(
              tx_types(services).fetch('send'),
              tx_types(services).fetch('recv'),
              tx_types(services).fetch('recv_check')
            )
            expect(backup_handles).not_to include(tx_types(services).fetch('local_send'))
            expect(
              node2.zfs_exists?(
                "#{branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), head_branch)}@#{@snap3.fetch('name')}",
                type: 'snapshot',
                timeout: 30
              )
            ).to be(true)
            transfers = transfer_evidence(@snap3.fetch('chain_id'))
            expect(transfers.length).to eq(2)
            expect(transfers.map { |row| [row.fetch('handle'), row.fetch('node_id')] }).to contain_exactly(
              [tx_types(services).fetch('send'), node1_id],
              [tx_types(services).fetch('recv'), node2_id]
            )
            expected_snapshot_ids = [@snap2.fetch('id'), @snap3.fetch('id')]
            transfers.each do |row|
              expect(row.values_at('done', 'status', 'result')).to eq([1, 1, 'ok'])
              expect(row.fetch('snapshots').map { |snapshot| snapshot.fetch('id') }).to eq(expected_snapshot_ids)
            end
            expect(receive_history_count(node2, restored_fs)).to be > before_receives
            expect(zfs_guid(node1, "#{@setup.fetch('primary_dataset_path')}@#{@snap3.fetch('name')}")).to eq(
              zfs_guid(node2, "#{restored_fs}@#{@snap3.fetch('name')}")
            )
            expect_backup_payload(@snap1, 'remote restore A')
            expect_backup_payload(@snap2, 'remote restore B')
            expect_backup_payload(@snap3, 'remote restore C')
          end
        end
      end
    '';
  }
)
