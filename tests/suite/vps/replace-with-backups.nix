import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ../storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };
  in
  {
    name = "vps-replace-with-backups";

    description = ''
      Replace a VPS with existing backups, verify backup datasets are renamed
      and database snapshot links remain aligned with the on-disk state.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../machines/cluster/1-node.nix args;

    testScript = common + ''
      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        prepare_node_queues(node)
        services.unlock_transaction_signing_key(passphrase: 'test')
        set_user_default_email_enabled(
          services,
          admin_user_id: admin_user_id,
          user_id: admin_user_id,
          enabled: false
        )
      end

      describe 'same-node VPS replace with backups', order: :defined do
        it 'moves backup history and keeps future backups incremental' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-replace-backups-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-replace-backups'
          dst_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-replace-backups-dst',
            filesystem: dst_pool_fs,
            role: 'hypervisor'
          )
          replace_backup_pool_fs = 'tank/backup-replace'
          backup_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-replace-backups-backup',
            filesystem: replace_backup_pool_fs,
            role: 'backup'
          )

          [src_pool, dst_pool, backup_pool].each do |pool|
            wait_for_pool_online(services, pool.fetch('id'))
          end

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-replace-backups',
            start: false
          )

          src_info = nil
          wait_until_block_succeeds(name: "source dataset info for VPS #{vps.fetch('id')}") do
            src_info = dataset_info(services, vps.fetch('id'))
            !src_info.nil?
          end

          backup_info = ensure_dataset_in_pool(
            services,
            admin_user_id: admin_user_id,
            dataset_id: src_info.fetch('dataset_id'),
            pool_id: backup_pool.fetch('id')
          )

          src_dataset_path = "#{primary_pool_fs}/#{src_info.fetch('dataset_full_name')}"
          old_backup_path = "#{replace_backup_pool_fs}/#{src_info.fetch('dataset_full_name')}"

          write_dataset_text(
            node,
            dataset_path: src_dataset_path,
            relative_path: 'root/backed-up-before-replace.txt',
            content: "backed-up before replace\n"
          )
          backed_up_snapshot = create_snapshot(
            services,
            dataset_id: src_info.fetch('dataset_id'),
            dip_id: src_info.fetch('dataset_in_pool_id'),
            label: 'backed up before replace'
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: src_info.fetch('dataset_in_pool_id'),
            dst_dip_id: backup_info.fetch('dataset_in_pool_id')
          )

          write_dataset_text(
            node,
            dataset_path: src_dataset_path,
            relative_path: 'root/local-before-replace.txt',
            content: "local before replace\n"
          )
          local_snapshot = create_snapshot(
            services,
            dataset_id: src_info.fetch('dataset_id'),
            dip_id: src_info.fetch('dataset_in_pool_id'),
            label: 'local before replace'
          )

          set_snapshot_retention(
            services,
            dip_id: src_info.fetch('dataset_in_pool_id'),
            min_snapshots: 0,
            max_snapshots: 2,
            snapshot_max_age: 31_536_000
          )

          response = vps_replace(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            node_id: node1_id,
            start: false,
            reason: 'replace backups integration'
          )
          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved],
            timeout: 1200
          )
          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          handles = chain_transactions(services, response.fetch('chain_id')).map do |row|
            row.fetch('handle')
          end
          chain_diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles
          }

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_diagnostic.inspect
          expect(handles.count(tx_types(services).fetch('local_send'))).to eq(1), chain_diagnostic.inspect
          expect(handles).to include(
            tx_types(services).fetch('create_snapshots'),
            tx_types(services).fetch('local_send'),
            tx_types(services).fetch('rename_dataset'),
            tx_types(services).fetch('vps_copy')
          ), chain_diagnostic.inspect
          expect(handles).not_to include(
            tx_types(services).fetch('destroy_dataset')
          ), chain_diagnostic.inspect

          replacement_info = nil
          wait_until_block_succeeds(name: "replacement dataset info for VPS #{response.fetch('replaced_vps_id')}") do
            replacement_info = dataset_info(services, response.fetch('replaced_vps_id'))
            !replacement_info.nil?
          end

          replacement_backup = dataset_in_pool_info(
            services,
            dataset_id: replacement_info.fetch('dataset_id'),
            pool_id: backup_pool.fetch('id')
          )
          new_backup_path = "#{replace_backup_pool_fs}/#{replacement_info.fetch('dataset_full_name')}"
          replacement_path = "#{dst_pool_fs}/#{replacement_info.fetch('dataset_full_name')}"

          wait_until_block_succeeds(name: "old backup dataset #{old_backup_path} was renamed") do
            !backup_dataset_exists?(node, old_backup_path)
          end
          wait_until_block_succeeds(name: "new backup dataset #{new_backup_path} exists") do
            backup_dataset_exists?(node, new_backup_path)
          end

          diagnostic = {
            chain_id: response.fetch('chain_id'),
            replacement_info: replacement_info,
            replacement_backup: replacement_backup
          }
          replace_snapshot_label = "Created for VPS replace #{vps.fetch('id')} -> #{response.fetch('replaced_vps_id')}"
          source_replace_snapshot = snapshot_row_by_label(
            services,
            dataset_id: src_info.fetch('dataset_id'),
            label: replace_snapshot_label
          )
          replacement_replace_snapshot = snapshot_row_by_label(
            services,
            dataset_id: replacement_info.fetch('dataset_id'),
            label: replace_snapshot_label
          )
          replace_snapshot_name = source_replace_snapshot.fetch('name')
          source_names = expect_dip_snapshots_match_zfs(
            services,
            node,
            dip_id: src_info.fetch('dataset_in_pool_id'),
            dataset_path: src_dataset_path,
            diagnostic: diagnostic
          )
          replacement_names = expect_dip_snapshots_match_zfs(
            services,
            node,
            dip_id: replacement_info.fetch('dataset_in_pool_id'),
            dataset_path: replacement_path,
            diagnostic: diagnostic
          )
          backup_names = expect_dip_snapshots_match_zfs(
            services,
            node,
            dip_id: replacement_backup.fetch('dataset_in_pool_id'),
            dataset_path: new_backup_path,
            diagnostic: diagnostic
          )

          expect(replacement_backup.fetch('dataset_in_pool_id')).to eq(
            backup_info.fetch('dataset_in_pool_id')
          ), diagnostic.inspect
          expect(current_history_id(services, replacement_info.fetch('dataset_id'))).to eq(
            current_history_id(services, src_info.fetch('dataset_id'))
          ), diagnostic.inspect
          expect(replacement_replace_snapshot.fetch('name')).to eq(replace_snapshot_name), diagnostic.merge(
            source_replace_snapshot: source_replace_snapshot,
            replacement_replace_snapshot: replacement_replace_snapshot
          ).inspect
          expect(replace_snapshot_name).to match(
            /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\z/
          ), diagnostic.inspect
          expect(source_names).to include(
            backed_up_snapshot.fetch('name'),
            local_snapshot.fetch('name'),
            replace_snapshot_name
          ), diagnostic.inspect
          expect(replacement_names).to include(replace_snapshot_name), diagnostic.inspect
          expect(backup_names).to include(
            backed_up_snapshot.fetch('name'),
            local_snapshot.fetch('name'),
            replace_snapshot_name
          ), diagnostic.inspect
          expect(read_dataset_text(
            node,
            dataset_path: replacement_path,
            relative_path: 'root/backed-up-before-replace.txt'
          )).to eq("backed-up before replace\n"), diagnostic.inspect
          expect(read_dataset_text(
            node,
            dataset_path: replacement_path,
            relative_path: 'root/local-before-replace.txt'
          )).to eq("local before replace\n"), diagnostic.inspect

          set_snapshot_retention(
            services,
            dip_id: replacement_info.fetch('dataset_in_pool_id'),
            min_snapshots: 0,
            max_snapshots: 20,
            snapshot_max_age: 31_536_000
          )
          set_snapshot_retention(
            services,
            dip_id: replacement_backup.fetch('dataset_in_pool_id'),
            min_snapshots: 0,
            max_snapshots: 20,
            snapshot_max_age: 31_536_000
          )

          tree_count_before = services.mariadb_scalar(sql: <<~SQL).to_i
            SELECT COUNT(*)
            FROM dataset_trees
            WHERE dataset_in_pool_id = #{Integer(replacement_backup.fetch('dataset_in_pool_id'))}
          SQL
          head_branch_before = head_branch_row(
            services,
            replacement_backup.fetch('dataset_in_pool_id')
          )

          write_dataset_text(
            node,
            dataset_path: replacement_path,
            relative_path: 'root/post-replace-backup.txt',
            content: "post replace backup\n"
          )
          post_replace_snapshot = create_snapshot(
            services,
            dataset_id: replacement_info.fetch('dataset_id'),
            dip_id: replacement_info.fetch('dataset_in_pool_id'),
            label: 'post replace backup'
          )
          fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: replacement_info.fetch('dataset_in_pool_id'),
            dst_dip_id: replacement_backup.fetch('dataset_in_pool_id')
          )

          tree_count_after = services.mariadb_scalar(sql: <<~SQL).to_i
            SELECT COUNT(*)
            FROM dataset_trees
            WHERE dataset_in_pool_id = #{Integer(replacement_backup.fetch('dataset_in_pool_id'))}
          SQL
          head_branch_after = head_branch_row(
            services,
            replacement_backup.fetch('dataset_in_pool_id')
          )
          head_branch_path_after = branch_dataset_path(
            replace_backup_pool_fs,
            replacement_info.fetch('dataset_full_name'),
            head_branch_after
          )
          replacement_names_after = expect_dip_snapshots_match_zfs(
            services,
            node,
            dip_id: replacement_info.fetch('dataset_in_pool_id'),
            dataset_path: replacement_path,
            diagnostic: diagnostic
          )
          backup_names_after = expect_dip_snapshots_match_zfs(
            services,
            node,
            dip_id: replacement_backup.fetch('dataset_in_pool_id'),
            dataset_path: new_backup_path,
            diagnostic: diagnostic
          )

          expect(tree_count_after).to eq(tree_count_before), {
            tree_count_before: tree_count_before,
            tree_count_after: tree_count_after,
            backup_names_after: backup_names_after
          }.inspect
          expect(head_branch_after.fetch('branch_id')).to eq(
            head_branch_before.fetch('branch_id')
          ), {
            head_branch_before: head_branch_before,
            head_branch_after: head_branch_after
          }.inspect
          expect(replacement_names_after).to include(post_replace_snapshot.fetch('name'))
          expect(backup_names_after).to include(post_replace_snapshot.fetch('name'))
          expect(read_dataset_text(
            node,
            dataset_path: head_branch_path_after,
            relative_path: 'root/post-replace-backup.txt'
          )).to eq("post replace backup\n")
        end
      end
    '';
  }
)
