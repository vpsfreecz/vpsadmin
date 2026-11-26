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
    };
  in
  {
    name = "storage-backup-multiple-destinations-remote";

    description = ''
      Create a VPS with two remote backup destinations, let one destination lag
      behind, and verify source rotation keeps the shared snapshot needed for
      the lagging destination. Preserve all existing snapshots before cleanup,
      retain backup history on partial failure, reject old gaps, and reenable
      with full then incremental transfers.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../machines/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote backups with multiple destinations', order: :defined do
        def write_marker(value)
          write_dataset_text(node1, dataset_path: @setup.fetch('primary_dataset_path'),
                             relative_path: 'var/tmp/backup-disable-marker', content: "#{value}\n")
        end

        def check_retained_contents
          @setup.fetch('dst_dip_ids').each do |label, destination|
            pool_fs = label == 'backup-a' ? 'tank/backup-a' : 'tank/backup-b'
            branch_entries_for_dip(services, destination).each do |entry|
              path = branch_dataset_path(pool_fs, @setup.fetch('dataset_full_name'), entry)
              expect(node2.zfs_exists?("#{path}@#{entry.fetch('snapshot_name')}", type: 'snapshot', timeout: 30)).to be(true)
              expect(read_dataset_text(
                node2, dataset_path: path,
                relative_path: ".zfs/snapshot/#{entry.fetch('snapshot_name')}/var/tmp/backup-disable-marker"
              )).to eq(@markers.fetch(entry.fetch('snapshot_id')))
            end
          end
        end

        it 'creates a VPS with one primary pool and two backup pools' do
          @setup = create_remote_backup_vps_with_backups(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-multi-dest',
            primary_pool_fs: primary_pool_fs,
            backup_pool_defs: [
              { label: 'backup-a', filesystem: 'tank/backup-a' },
              { label: 'backup-b', filesystem: 'tank/backup-b' }
            ]
          )
          services.succeeds('systemctl stop vpsadmin-scheduler.service')
          @environment_plan_id = ensure_dataset_backup_plan(services, dataset_id: @setup.fetch('dataset_id'))
          @markers = {}
          @setup.fetch('dst_dip_ids').each_value do |destination|
            set_snapshot_retention(services, dip_id: destination, min_snapshots: 100,
                                   max_snapshots: 100, snapshot_max_age: 0)
          end
        end

        it 'keeps the shared source snapshot needed by a lagging remote destination' do
          dst_a = @setup.fetch('dst_dip_ids').fetch('backup-a')
          dst_b = @setup.fetch('dst_dip_ids').fetch('backup-b')

          set_snapshot_retention(
            services,
            dip_id: @setup.fetch('src_dip_id'),
            min_snapshots: 1,
            max_snapshots: 1,
            snapshot_max_age: 0
          )

          marker = write_marker('multi-dest-s1')
          @snap1 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'multi-dest-s1'
          )
          @markers[@snap1.fetch('id')] = marker
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_a
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_b
          )

          marker = write_marker('multi-dest-s2')
          @snap2 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'multi-dest-s2'
          )
          @markers[@snap2.fetch('id')] = marker
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_a
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_b
          )

          marker = write_marker('multi-dest-s3')
          @snap3 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'multi-dest-s3'
          )
          @markers[@snap3.fetch('id')] = marker
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_b
          )

          source_names = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).map { |row| row.fetch('name') }

          expect(source_names).to include(@snap2.fetch('name'), @snap3.fetch('name'))
          expect(source_names).not_to include(@snap1.fetch('name'))

          catch_up = fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: dst_a
          )
          handles = chain_transactions(services, catch_up.fetch('chain_id')).map { |row| row.fetch('handle') }

          expect(branch_rows_for_dip(services, dst_a).count).to eq(1)
          expect(head_tree_row(services, dst_a).fetch('tree_index')).to eq(0)
          expect(handles).to include(
            tx_types(services).fetch('send'),
            tx_types(services).fetch('recv'),
            tx_types(services).fetch('recv_check')
          )
          expect(handles).not_to include(tx_types(services).fetch('local_send'))
          expect(handles).not_to include(tx_types(services).fetch('create_tree'))
          expect(handles).not_to include(tx_types(services).fetch('branch_dataset'))
          expect(handles.count { |handle| handle == tx_types(services).fetch('send') }).to eq(1)
          expect(handles.count { |handle| handle == tx_types(services).fetch('recv') }).to eq(1)
          expect(handles.count { |handle| handle == tx_types(services).fetch('recv_check') }).to eq(1)
        end

        it 'preserves normally lagging targets before irreversible partial cleanup in one task' do
          source_id = @setup.fetch('src_dip_id')
          destination_a = @setup.fetch('dst_dip_ids').fetch('backup-a')
          set_snapshot_retention(services, dip_id: source_id, min_snapshots: 100,
                                 max_snapshots: 100, snapshot_max_age: 0)
          later = []
          (4..6).each do |number|
            marker = write_marker("multi-dest-s#{number}")
            snap = create_snapshot(services, dataset_id: @setup.fetch('dataset_id'),
                                   dip_id: source_id, label: "multi-dest-s#{number}")
            @markers[snap.fetch('id')] = marker
            later << snap
            if number < 6
              fire_backup(services, admin_user_id: admin_user_id,
                          src_dip_id: source_id, dst_dip_id: destination_a)
            end
          end
          @source_rows = snapshot_rows_for_dip(services, source_id)
          @plans_before = dataset_backup_plan_rows(services, source_id)
          expect(@plans_before).not_to be_empty
          @old_entries = @setup.fetch('dst_dip_ids').transform_values { |destination| branch_entries_for_dip(services, destination) }
          @live_marker = write_marker('unsnapshotted live state before cleanup')
          @live_checksum = file_checksum(node1, dataset_path: @setup.fetch('primary_dataset_path'),
                                        relative_path: 'var/tmp/backup-disable-marker')

          held = @source_rows.fetch(-2)
          held_path = "#{@setup.fetch('primary_dataset_path')}@#{held.fetch('name')}"
          node1.succeeds("zfs hold disable-backups-test #{Shellwords.escape(held_path)}")
          begin
            response = disable_backups(services, dataset_id: @setup.fetch('dataset_id'))
            # No caller continuation: the accepted task reaches cleanup itself.
            terminal = wait_for_chain_states_local(services, response.fetch('chain_id'), %i[done failed fatal resolved], timeout: 1200)
            expect(terminal).to eq(services.class::CHAIN_STATES.fetch(:failed))
            transactions = chain_transactions(services, response.fetch('chain_id'))
            types = tx_types(services)
            checks = transactions.select { |tx| tx.fetch('handle') == types.fetch('recv_check') }
            destroys = transactions.select { |tx| tx.fetch('handle') == types.fetch('destroy_snapshot') }
            expect(checks).not_to be_empty
            expect(destroys.size).to eq(@source_rows.size)
            expect(checks.map { |tx| tx.fetch('id') }.max).to be < destroys.first.fetch('id')
            boundary = transactions.index { |tx| tx.fetch('reversible') == 0 }
            expect(boundary).not_to be_nil
            expect(transactions[boundary..].map { |tx| tx.fetch('reversible') }).to all(eq(0))
            expect(backup_send_snapshot_names(services, response.fetch('chain_id'))).to match_array([
              later.last(2).map { |snap| snap.fetch('name') },
              [@snap3.fetch('name')] + later.map { |snap| snap.fetch('name') }
            ])
            expect(transactions.map { |tx| tx.fetch('handle') }).not_to include(types.fetch('create_tree'))
            remaining = snapshot_rows_for_dip(services, source_id)
            expect(remaining.map { |row| row.fetch('id') }).to include(held.fetch('id'), @source_rows.last.fetch('id'))
            expect(remaining.map { |row| row.fetch('id') }).not_to include(@source_rows.first.fetch('id'))
            expect(dataset_backup_plan_rows(services, source_id)).to be_empty
            @preserved_entries = @setup.fetch('dst_dip_ids').transform_values do |destination|
              expect(confirmed_backup_snapshot_ids(services, destination)).to include(*@source_rows.map { |row| row.fetch('id') })
              expect(head_tree_row(services, destination)).to be_nil
              expect(branch_rows_for_dip(services, destination).map { |row| row.fetch('head') }).to all(eq(0))
              branch_entries_for_dip(services, destination)
            end
            @old_entries.each do |label, entries|
              expect(@preserved_entries.fetch(label).map { |entry| entry.fetch('entry_id') }).to include(*entries.map { |entry| entry.fetch('entry_id') })
            end
            expect(file_checksum(node1, dataset_path: @setup.fetch('primary_dataset_path'),
                                 relative_path: 'var/tmp/backup-disable-marker')).to eq(@live_checksum)
            check_retained_contents
          ensure
            node1.succeeds("zfs release disable-backups-test #{Shellwords.escape(held_path)}")
          end
        end

        it 'deliberately retries remaining cleanup without changing retained backups or live data' do
          response = disable_backups(services, dataset_id: @setup.fetch('dataset_id'))
          services.wait_for_chain_state(response.fetch('chain_id'), state: :done)
          expect(snapshot_rows_for_dip(services, @setup.fetch('src_dip_id'))).to be_empty
          expect(dataset_backup_plan_rows(services, @setup.fetch('src_dip_id'))).to be_empty
          expect(read_dataset_text(node1, dataset_path: @setup.fetch('primary_dataset_path'),
                                   relative_path: 'var/tmp/backup-disable-marker')).to eq(@live_marker)
          expect(file_checksum(node1, dataset_path: @setup.fetch('primary_dataset_path'),
                               relative_path: 'var/tmp/backup-disable-marker')).to eq(@live_checksum)
          @setup.fetch('dst_dip_ids').each do |label, destination|
            expect(branch_entries_for_dip(services, destination).map { |row| row.fetch('entry_id') }).to eq(
              @preserved_entries.fetch(label).map { |row| row.fetch('entry_id') }
            )
          end
          wait_for_vps_running(services, @setup.fetch('vps_id'))
          check_retained_contents
        end

        it 'reenables with a full first stream into new trees, then transfers incrementally' do
          services.vpsadminctl.succeeds(
            args: ['dataset.plan', 'create', @setup.fetch('dataset_id').to_s],
            parameters: { environment_dataset_plan: @environment_plan_id }
          )
          first_marker = write_marker('reenabled first snapshot')
          first = create_snapshot(services, dataset_id: @setup.fetch('dataset_id'),
                                  dip_id: @setup.fetch('src_dip_id'), label: 'reenabled-first')
          @markers[first.fetch('id')] = first_marker
          @reenabled_first = first
          heads = {}
          @setup.fetch('dst_dip_ids').each do |label, destination|
            response = fire_backup(services, admin_user_id: admin_user_id,
                                   src_dip_id: @setup.fetch('src_dip_id'), dst_dip_id: destination)
            head = head_tree_row(services, destination)
            previous = @preserved_entries.fetch(label).map { |row| row.fetch('tree_index') }.max
            expect(head.fetch('tree_index')).to be > previous
            expect(backup_send_snapshot_names(services, response.fetch('chain_id'))).to eq([[first.fetch('name')]])
            heads[label] = head.fetch('tree_id')
          end
          second_marker = write_marker('reenabled incremental snapshot')
          second = create_snapshot(services, dataset_id: @setup.fetch('dataset_id'),
                                   dip_id: @setup.fetch('src_dip_id'), label: 'reenabled-second')
          @markers[second.fetch('id')] = second_marker
          @setup.fetch('dst_dip_ids').each do |label, destination|
            response = fire_backup(services, admin_user_id: admin_user_id,
                                   src_dip_id: @setup.fetch('src_dip_id'), dst_dip_id: destination)
            expect(head_tree_row(services, destination).fetch('tree_id')).to eq(heads.fetch(label))
            expect(backup_send_snapshot_names(services, response.fetch('chain_id'))).to eq([[first.fetch('name'), second.fetch('name')]])
            expect(branch_entries_for_dip(services, destination).map { |row| row.fetch('entry_id') }).to include(
              *@preserved_entries.fetch(label).map { |row| row.fetch('entry_id') }
            )
          end
          check_retained_contents
        end

        it 'rejects an older gap below a newer head without queueing cleanup or changing source and plans' do
          destination = @setup.fetch('dst_dip_ids').fetch('backup-a')
          gap = snapshot_rows_for_dip(services, destination).find { |row| row.fetch('id') == @reenabled_first.fetch('id') }
          deletion = destroy_snapshot_in_pool(services, admin_user_id: admin_user_id,
                                              sip_id: gap.fetch('snapshot_in_pool_id'))
          services.wait_for_chain_state(deletion.fetch('chain_id'), state: :done)
          source_before = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id'))
          plans_before = dataset_backup_plan_rows(services, @setup.fetch('src_dip_id'))
          entries_before = @setup.fetch('dst_dip_ids').transform_values { |copy| branch_entries_for_dip(services, copy) }
          chain_count = services.mariadb_scalar(sql: "SELECT COUNT(*) FROM transaction_chains WHERE type = 'TransactionChains::Dataset::DisableBackups'")
          _, rejected = services.vpsadminctl.fails(
            args: ['dataset', 'disable_backups', @setup.fetch('dataset_id').to_s],
            opts: { block: false }, parameters: { backup_first: true, recursive: false }
          )
          expect(rejected.to_s).to include("ordinary transfer cannot preserve snapshot #{@reenabled_first.fetch('id')} on backup #{destination}")
          expect(services.mariadb_scalar(sql: "SELECT COUNT(*) FROM transaction_chains WHERE type = 'TransactionChains::Dataset::DisableBackups'")).to eq(chain_count)
          expect(snapshot_rows_for_dip(services, @setup.fetch('src_dip_id'))).to eq(source_before)
          expect(dataset_backup_plan_rows(services, @setup.fetch('src_dip_id'))).to eq(plans_before)
          source_before.each do |snapshot|
            expect(read_dataset_text(
              node1, dataset_path: @setup.fetch('primary_dataset_path'),
              relative_path: ".zfs/snapshot/#{snapshot.fetch('name')}/var/tmp/backup-disable-marker"
            )).to eq(@markers.fetch(snapshot.fetch('id')))
          end
          @setup.fetch('dst_dip_ids').each do |label, copy|
            expect(branch_entries_for_dip(services, copy)).to eq(entries_before.fetch(label))
          end
          check_retained_contents
        end
      end
    '';
  }
)
