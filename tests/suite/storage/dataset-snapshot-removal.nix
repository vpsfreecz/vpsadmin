import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    clusterSeed = import ../../../api/db/seeds/test-2-node.nix;
    common = import ./remote-common.nix {
      adminUserId = seed.adminUser.id;
      node1Id = clusterSeed.nodes.node1.id;
      node2Id = clusterSeed.nodes.node2.id;
    };
  in
  {
    name = "storage-dataset-snapshot-removal";
    description = ''
      Remove reviewed source and multi-pool backup history while preserving
      live files, identities, quotas, VPS state, backup shells and unrelated
      history. Exercise recursion, stale review, partial failure and retained
      plans creating fresh full and incremental backups.
    '';
    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];
    machines = import ../../machines/cluster/2-node.nix args;

    testScript =
      common
      + import ./dataset-snapshot-removal-common.nix
      + ''
        describe 'reviewed dataset snapshot removal', order: :defined do
          def root_backups
            @setup.fetch('dst_dip_ids').map { |label, id| [id, @setup.fetch('backup_dataset_paths').fetch(label)] }
          end

          def root_proof
            {
              'source' => source_proof(@setup.fetch('dataset_id'), @setup.fetch('src_dip_id'), @setup.fetch('primary_dataset_path')),
              'vps' => vps_row(services, @setup.fetch('vps_id')),
              'resources' => vps_resource_uses(services, @setup.fetch('vps_id')),
              'copies' => root_backups.map do |id, path|
                dataset_in_pool_row(services, id).merge('guid' => zfs_guid(node2, path))
              end
            }
          end

          def expect_live_data_preserved
            expect(root_proof).to eq(@root_proof)
            wait_for_vps_running(services, @setup.fetch('vps_id'))
            expect(source_proof(@child.fetch('dataset_id'), @child.fetch('dip_id'), @child.fetch('dataset_path'))).to eq(@child_proof)
            expect(source_proof(@unrelated.fetch('dataset_id'), @unrelated.fetch('dataset_in_pool_id'), @unrelated_path)).to eq(@unrelated_proof)
            expect(snapshot_rows_for_dip(services, @unrelated.fetch('dataset_in_pool_id'))).to eq(@unrelated_snapshots)
            expect(backup_storage_proof(@unrelated_backup, @unrelated_backup_path)).to eq(@unrelated_backup_proof)
            expect(dataset_backup_plan_rows(services, @unrelated.fetch('dataset_in_pool_id'))).to eq(@unrelated_plans)
            expect(cached_plan_jobs(@unrelated.fetch('dataset_in_pool_id'))).to eq(@unrelated_jobs)
          end

          it 'prepares nested rollback, shared and empty histories on two backup pools' do
            @setup = create_remote_backup_vps_with_backups(
              services, primary_node: node1, backup_node: node2,
              admin_user_id: admin_user_id, primary_node_id: node1_id, backup_node_id: node2_id,
              hostname: 'snapshot-removal', primary_pool_fs: primary_pool_fs,
              backup_pool_defs: [
                { label: 'backup-a', filesystem: 'tank/backup-a' },
                { label: 'backup-b', filesystem: 'tank/backup-b' }
              ]
            )
            services.succeeds('systemctl stop vpsadmin-scheduler.service')
            [@setup.fetch('src_dip_id'), *@setup.fetch('dst_dip_ids').values].each do |id|
              set_snapshot_retention(services, dip_id: id, min_snapshots: 100, max_snapshots: 100, snapshot_max_age: 0)
            end
            build_repeated_rollback_topology(
              services, admin_user_id: admin_user_id, dataset_id: @setup.fetch('dataset_id'),
              src_dip_id: @setup.fetch('src_dip_id'), dst_dip_id: @setup.fetch('dst_dip_ids').fetch('backup-a'),
              vps_id: @setup.fetch('vps_id'), label_prefix: 'removal'
            )
            fire_backup(services, admin_user_id: admin_user_id, src_dip_id: @setup.fetch('src_dip_id'),
                        dst_dip_id: @setup.fetch('dst_dip_ids').fetch('backup-b'))
            @extra = add_shared_and_empty_history(*root_backups.first)
            graph = backup_storage_proof(*root_backups.first)
            entries = graph.fetch('db').fetch('entries')
            expect(graph.fetch('db').fetch('branches').count).to be >= 5
            expect(entries.group_by { |e| e.fetch('snapshot_in_pool_id') }.values.any? { |rows| rows.size > 1 }).to be(true)
            origins = entries.map { |e| e.fetch('parent_entry_id') }.compact
            expect(entries.any? { |e| origins.include?(e.fetch('entry_id')) && e.fetch('parent_entry_id') }).to be(true)

            @child = create_descendant_dataset(
              services, admin_user_id: admin_user_id, parent_dataset_id: @setup.fetch('dataset_id'),
              name: 'child', pool_fs: primary_pool_fs
            )
            child_destination = ensure_dataset_in_pool(
              services, admin_user_id: admin_user_id, dataset_id: @child.fetch('dataset_id'),
              pool_id: @setup.fetch('backup_pool_ids').fetch('backup-a')
            )
            @child_backups = [[child_destination.fetch('dataset_in_pool_id'), "tank/backup-a/#{@child.fetch('full_name')}"]]
            write_dataset_text(node1, dataset_path: @child.fetch('dataset_path'), relative_path: 'var/tmp/removal-marker', content: "child stays live\n")
            create_and_backup_snapshot(
              services, admin_user_id: admin_user_id, dataset_id: @child.fetch('dataset_id'),
              src_dip_id: @child.fetch('dip_id'), dst_dip_id: @child_backups.first.first, label: 'child-before-removal'
            )
            ensure_dataset_backup_plan(services, dataset_id: @child.fetch('dataset_id'))
            @child_snapshots = snapshot_rows_for_dip(services, @child.fetch('dip_id'))
            @child_backup_proof = backup_storage_proof(*@child_backups.first)

            @unrelated = create_top_level_dataset(
              services, admin_user_id: admin_user_id, pool_id: @setup.fetch('primary_pool_id'), dataset_name: 'removal-unrelated'
            )
            @unrelated_path = "#{primary_pool_fs}/#{@unrelated.fetch('dataset_full_name')}"
            destination = ensure_dataset_in_pool(
              services, admin_user_id: admin_user_id, dataset_id: @unrelated.fetch('dataset_id'),
              pool_id: @setup.fetch('backup_pool_ids').fetch('backup-a')
            )
            @unrelated_backup = destination.fetch('dataset_in_pool_id')
            @unrelated_backup_path = "tank/backup-a/#{@unrelated.fetch('dataset_full_name')}"
            write_dataset_text(node1, dataset_path: @unrelated_path, relative_path: 'var/tmp/removal-marker', content: "unrelated stays live\n")
            create_and_backup_snapshot(
              services, admin_user_id: admin_user_id, dataset_id: @unrelated.fetch('dataset_id'),
              src_dip_id: @unrelated.fetch('dataset_in_pool_id'), dst_dip_id: @unrelated_backup, label: 'unrelated-removal'
            )
            ensure_dataset_backup_plan(services, dataset_id: @unrelated.fetch('dataset_id'))
            @unrelated_jobs = cached_plan_jobs(@unrelated.fetch('dataset_in_pool_id'))
            @unrelated_plans = dataset_backup_plan_rows(services, @unrelated.fetch('dataset_in_pool_id'))
            @unrelated_snapshots = snapshot_rows_for_dip(services, @unrelated.fetch('dataset_in_pool_id'))
            @unrelated_backup_proof = backup_storage_proof(@unrelated_backup, @unrelated_backup_path)
            ensure_dataset_backup_plan(services, dataset_id: @setup.fetch('dataset_id'))
            @jobs = cached_plan_jobs(@setup.fetch('src_dip_id'))
            expect(@jobs.map { |job| job.fetch('kind') }).to include('backup', 'group_snapshot')
            @plans = dataset_backup_plan_rows(services, @setup.fetch('src_dip_id'))
            expect(@plans).not_to be_empty
            write_dataset_text(node1, dataset_path: @setup.fetch('primary_dataset_path'), relative_path: 'var/tmp/removal-marker', content: "unsnapshotted live source\n")
            @root_proof = root_proof
            @child_proof = source_proof(@child.fetch('dataset_id'), @child.fetch('dip_id'), @child.fetch('dataset_path'))
            @unrelated_proof = source_proof(@unrelated.fetch('dataset_id'), @unrelated.fetch('dataset_in_pool_id'), @unrelated_path)
            # Closed destinations must be included in the destructive inventory.
            services.api_ruby_json(code: "Pool.find(#{@setup.fetch('backup_pool_ids').fetch('backup-b')}).update!(is_open: 0); puts JSON.dump(true)")
          end

          it 'previews the complete root-only inventory without creating a task or changing storage' do
            before = root_backups.map { |id, path| backup_storage_proof(id, path) }
            count = removal_chain_count
            @preview = preview_snapshot_removal(@setup.fetch('dataset_id'))
            manifest = @preview.fetch('manifest')
            expect(manifest.fetch('options')).to eq('recursive' => false, 'disable_plans' => true)
            expect(manifest.fetch('datasets').map { |row| row.fetch('id') }).to eq([@setup.fetch('dataset_id')])
            expect(manifest.fetch('copies').map { |row| row.fetch('id') }).to match_array([@setup.fetch('src_dip_id'), *root_backups.map(&:first)])
            expect(manifest.fetch('copies').find { |row| row.fetch('id') == root_backups.last.first }.fetch('pool_open')).to be(false)
            expect(manifest.fetch('trees').map { |row| row.fetch('id') }).to include(@extra.fetch('tree_id'), @extra.fetch('empty_tree_id'))
            expect(manifest.fetch('branches').map { |row| row.fetch('id') }).to include(@extra.fetch('empty_branch_id'))
            expected_locations = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).map do |row|
              [row.fetch('snapshot_in_pool_id'), nil]
            end
            root_backups.each do |id, _|
              expected_locations.concat(branch_entries_for_dip(services, id).map { |row| [row.fetch('snapshot_in_pool_id'), row.fetch('entry_id')] })
            end
            expect(manifest.fetch('snapshot_locations').map { |row| [row.fetch('snapshot_in_pool_id'), row.fetch('snapshot_in_pool_in_branch_id')] }).to match_array(expected_locations)
            %w[datasets copies snapshot_locations trees branches plans].each do |key|
              expect(manifest.fetch('counts').fetch(key)).to eq(manifest.fetch(key).size)
            end
            expect(manifest.fetch('counts').fetch('snapshots')).to eq(manifest.fetch('snapshot_locations').map { |row| row.fetch('snapshot_id') }.uniq.size)
            expect(manifest.fetch('plans').map { |row| row.fetch('action') }).to all(eq('remove'))
            expect(manifest.fetch('counts').fetch('plans_to_disable')).to eq(@plans.size)
            expect(preview_snapshot_removal(@setup.fetch('dataset_id'))).to eq(@preview)
            expect(removal_chain_count).to eq(count)
            expect(root_backups.map { |id, path| backup_storage_proof(id, path) }).to eq(before)
            expect(dataset_backup_plan_rows(services, @setup.fetch('src_dip_id'))).to eq(@plans)
            expect_live_data_preserved
          end

          it 'rejects stale review and an unavailable closed destination before any deletion' do
            create_snapshot(services, dataset_id: @setup.fetch('dataset_id'), dip_id: @setup.fetch('src_dip_id'), label: 'review-drift')
            source_before = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id'))
            backups_before = root_backups.map { |id, path| backup_storage_proof(id, path) }
            count = removal_chain_count
            _, rejected = services.vpsadminctl.fails(
              args: ['dataset', 'remove_snapshots', @setup.fetch('dataset_id').to_s], opts: { block: false },
              parameters: { recursive: false, disable_plans: true, manifest_digest: @preview.fetch('manifest_digest') }
            )
            expect(rejected.to_s).to include('stale_preview')
            @preview = preview_snapshot_removal(@setup.fetch('dataset_id'))
            pool_id = @setup.fetch('backup_pool_ids').fetch('backup-b')
            services.api_ruby_json(code: "Pool.find(#{pool_id}).update!(maintenance_lock: MaintenanceLock.maintain_lock(:lock)); puts JSON.dump(true)")
            begin
              services.vpsadminctl.fails(
                args: ['dataset', 'remove_snapshots', @setup.fetch('dataset_id').to_s], opts: { block: false },
                parameters: { recursive: false, disable_plans: true, manifest_digest: @preview.fetch('manifest_digest') }
              )
            ensure
              services.api_ruby_json(code: "Pool.find(#{pool_id}).update!(maintenance_lock: MaintenanceLock.maintain_lock(:no)); puts JSON.dump(true)")
            end
            expect(removal_chain_count).to eq(count)
            expect(snapshot_rows_for_dip(services, @setup.fetch('src_dip_id'))).to eq(source_before)
            expect(root_backups.map { |id, path| backup_storage_proof(id, path) }).to eq(backups_before)
            expect(dataset_backup_plan_rows(services, @setup.fetch('src_dip_id'))).to eq(@plans)
            expect_live_data_preserved
          end

          it 'reports partial backup deletion, reconciles actual effects, and requires a fresh review for retry' do
            destination, path = root_backups.last
            held_entry = branch_entries_for_dip(services, destination).first
            held_path = "#{branch_dataset_path('tank/backup-b', @setup.fetch('dataset_full_name'), held_entry)}@#{held_entry.fetch('snapshot_name')}"
            source_before = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id'))
            first_before = backup_storage_proof(*root_backups.first)
            node2.succeeds("zfs hold snapshot-removal-test #{Shellwords.escape(held_path)}", timeout: 60)
            begin
              @preview = preview_snapshot_removal(@setup.fetch('dataset_id'))
              id = remove_reviewed_snapshots(@setup.fetch('dataset_id'), @preview)
              state = wait_for_chain_states_local(services, id, %i[done failed fatal resolved], timeout: 1200)
            expect_removal_order(id, @preview)
              expect(state).to eq(services.class::CHAIN_STATES.fetch(:failed)), chain_failure_details(services, id).inspect
              expect(chain_failure_details(services, id)).not_to be_empty
              wait_for_chain_locks_released(services, id)
              first = backup_storage_proof(*root_backups.first)
              expect(first.fetch('db').fetch('entries').size).to be < first_before.fetch('db').fetch('entries').size
              removed_paths = first_before.fetch('physical') - first.fetch('physical')
              expect(removed_paths.grep(/@/)).not_to be_empty
              remaining = backup_storage_proof(destination, path)
              expect(remaining.fetch('snapshots')).not_to be_empty
              expect(node2.zfs_exists?(held_path, type: 'snapshot', timeout: 30)).to be(true)
              expect(snapshot_rows_for_dip(services, @setup.fetch('src_dip_id'))).to eq(source_before)
              expect(dataset_backup_plan_rows(services, @setup.fetch('src_dip_id'))).to be_empty
              transactions = chain_transactions(services, id)
              boundary = transactions.index { |tx| tx.fetch('reversible') == 0 }
              expect(boundary).not_to be_nil
              expect(transactions[boundary..].map { |tx| tx.fetch('reversible') }).to all(eq(0))
              expect_live_data_preserved
            ensure
              node2.succeeds("zfs release snapshot-removal-test #{Shellwords.escape(held_path)}", timeout: 60)
            end
            count = removal_chain_count
            _, rejected = services.vpsadminctl.fails(
              args: ['dataset', 'remove_snapshots', @setup.fetch('dataset_id').to_s], opts: { block: false },
              parameters: { manifest_digest: @preview.fetch('manifest_digest') }
            )
            expect(rejected.to_s).to include('stale_preview')
            expect(removal_chain_count).to eq(count)
            fresh = preview_snapshot_removal(@setup.fetch('dataset_id'))
            expect(fresh.fetch('manifest_digest')).not_to eq(@preview.fetch('manifest_digest'))
            expect_removal_done(remove_reviewed_snapshots(@setup.fetch('dataset_id'), fresh))
            expect_history_removed(@setup.fetch('dataset_id'), @setup.fetch('src_dip_id'), @setup.fetch('primary_dataset_path'), root_backups)
            expect(snapshot_rows_for_dip(services, @child.fetch('dip_id'))).to eq(@child_snapshots)
            expect(backup_storage_proof(*@child_backups.first)).to eq(@child_backup_proof)
            expect_live_data_preserved
          end

          it 'skips stale scheduled jobs and removes descendants only with explicit recursion' do
            # Feed the real chain entry points the IDs/members cached before plan
            # removal. A's DB concurrency specs cover the concurrently loaded job.
            expect(run_cached_jobs(@jobs, @setup.fetch('src_dip_id'))).to all(be_nil)
            expect_history_removed(@setup.fetch('dataset_id'), @setup.fetch('src_dip_id'), @setup.fetch('primary_dataset_path'), root_backups)
            fresh = preview_snapshot_removal(@setup.fetch('dataset_id'), recursive: true, disable_plans: true)
            expect(fresh.fetch('manifest').fetch('datasets').map { |row| row.fetch('id') }).to match_array([@setup.fetch('dataset_id'), @child.fetch('dataset_id')])
            expect_removal_done(remove_reviewed_snapshots(@setup.fetch('dataset_id'), fresh, recursive: true, disable_plans: true))
            expect_history_removed(@child.fetch('dataset_id'), @child.fetch('dip_id'), @child.fetch('dataset_path'), @child_backups)
            expect(dataset_backup_plan_rows(services, @child.fetch('dip_id'))).to be_empty
            expect_live_data_preserved
          end

          it 'retains explicitly selected plans and creates a full first stream then an incremental' do
            services.api_ruby_json(code: "Pool.find(#{@setup.fetch('backup_pool_ids').fetch('backup-b')}).update!(is_open: 1); puts JSON.dump(true)")
            ensure_dataset_backup_plan(services, dataset_id: @setup.fetch('dataset_id'))
            plans = dataset_backup_plan_rows(services, @setup.fetch('src_dip_id'))
            create_snapshot(services, dataset_id: @setup.fetch('dataset_id'), dip_id: @setup.fetch('src_dip_id'), label: 'one-time-purge')
            root_backups.each do |destination, _|
              fire_backup(services, admin_user_id: admin_user_id, src_dip_id: @setup.fetch('src_dip_id'), dst_dip_id: destination)
            end
            preview = preview_snapshot_removal(@setup.fetch('dataset_id'), recursive: false, disable_plans: false)
            expect(preview.fetch('manifest').fetch('plans').map { |row| row.fetch('action') }).to all(eq('retain'))
            expect(preview.fetch('manifest').fetch('counts').fetch('plans_to_disable')).to eq(0)
            expect_removal_done(remove_reviewed_snapshots(@setup.fetch('dataset_id'), preview, recursive: false, disable_plans: false))
            expect_history_removed(@setup.fetch('dataset_id'), @setup.fetch('src_dip_id'), @setup.fetch('primary_dataset_path'), root_backups)
            expect(dataset_backup_plan_rows(services, @setup.fetch('src_dip_id'))).to eq(plans)
            # Execute the retained jobs through their normal chain entry points.
            jobs = cached_plan_jobs(@setup.fetch('src_dip_id'))
            group = jobs.select { |job| job.fetch('kind') == 'group_snapshot' }
            backups = jobs.select { |job| job.fetch('kind') == 'backup' }
            expect(group.size).to eq(1)
            # The ordinary daily plan selects one open backup destination.
            # Exercise that retained action and use an ordinary explicit backup
            # for the other pool, preserving both-pool continuation coverage.
            expect(backups.size).to eq(1)
            scheduled_destination = backups.fetch(0).fetch('destination')
            expect(root_backups.map(&:first)).to include(scheduled_destination)
            continue_backup = lambda do |destination|
              if destination == scheduled_destination
                run_cached_jobs(backups, @setup.fetch('src_dip_id')).fetch(0)
              else
                fire_backup(services, admin_user_id: admin_user_id,
                            src_dip_id: @setup.fetch('src_dip_id'), dst_dip_id: destination).fetch('chain_id')
              end
            end
            run_cached_jobs(group, @setup.fetch('src_dip_id')).each { |id| expect_removal_done(id) }
            first = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).last
            root_backups.each do |destination, _|
              id = continue_backup.call(destination)
              expect_removal_done(id)
              expect(chain_transactions(services, id).map { |tx| tx.fetch('handle') }).to include(tx_types(services).fetch('create_tree'))
              expect(backup_send_snapshot_names(services, id)).to eq([[first.fetch('name')]])
            end
            heads = root_backups.map { |id, _| head_tree_row(services, id) }
            run_cached_jobs(group, @setup.fetch('src_dip_id')).each { |id| expect_removal_done(id) }
            second = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).last
            expect(second.fetch('id')).not_to eq(first.fetch('id'))
            root_backups.each do |destination, _|
              id = continue_backup.call(destination)
              expect_removal_done(id)
              expect(chain_transactions(services, id).map { |tx| tx.fetch('handle') }).not_to include(tx_types(services).fetch('create_tree'))
              expect(backup_send_snapshot_names(services, id)).to eq([[first.fetch('name'), second.fetch('name')]])
            end
            expect(root_backups.map { |id, _| head_tree_row(services, id) }).to eq(heads)
            expect(cached_plan_jobs(@setup.fetch('src_dip_id'))).to eq(jobs)
            root_backups.each do |id, path|
              report = backup_storage_proof(id, path)
              expect(report.fetch('snapshots').map { |row| row.fetch('id') }).to include(first.fetch('id'), second.fetch('id'))
              branch = head_branch_row(services, id)
              branch_path = branch_dataset_path(path.split('/')[0..1].join('/'), @setup.fetch('dataset_full_name'), branch)
              expect(read_dataset_text(node2, dataset_path: branch_path, relative_path: ".zfs/snapshot/#{second.fetch('name')}/var/tmp/removal-marker")).to eq(@root_proof.fetch('source').fetch('text'))
            end
            expect_live_data_preserved
          end
        end
      '';
  }
)
