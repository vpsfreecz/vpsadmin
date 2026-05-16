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
    name = "storage-branching-shared-snapshot-prune";

    description = ''
      Prune one backup branch entry for a snapshot shared with the current head
      branch and verify the shared metadata remains usable for incrementals.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../machines/cluster/2-node.nix args;

    testScript = common + ''
      describe 'pruning a shared backup branch snapshot', order: :defined do
        it 'keeps shared SnapshotInPool metadata and continues incrementally' do
          setup = create_remote_backup_dataset(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            dataset_name: 'storage-shared-snapshot-prune',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

          snap1 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'shared-prune-s1'
          )
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'shared-prune-s2'
          )

          old_branch = head_branch_row(services, setup.fetch('dst_dip_id'))
          old_branch_path = branch_dataset_path(
            backup_pool_fs,
            setup.fetch('dataset_full_name'),
            old_branch
          )
          shared_sip_id = snapshot_rows_for_dip(services, setup.fetch('dst_dip_id')).detect do |row|
            row.fetch('name') == snap1.fetch('name')
          end.fetch('snapshot_in_pool_id')

          shared = services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}

            dip = DatasetInPool.find(#{Integer(setup.fetch('dst_dip_id'))})
            DatasetTree.where(dataset_in_pool: dip).update_all(head: false)
            Branch.joins(:dataset_tree).where(dataset_trees: { dataset_in_pool_id: dip.id }).update_all(head: false)

            tree = DatasetTree.create!(
              dataset_in_pool: dip,
              index: dip.dataset_trees.maximum(:index).to_i + 1,
              head: true,
              confirmed: DatasetTree.confirmed(:confirmed)
            )
            branch = Branch.create!(
              dataset_tree: tree,
              name: 'shared',
              index: 0,
              head: true,
              confirmed: Branch.confirmed(:confirmed)
            )
            entry = SnapshotInPoolInBranch.create!(
              snapshot_in_pool_id: #{Integer(shared_sip_id)},
              branch: branch,
              confirmed: SnapshotInPoolInBranch.confirmed(:confirmed)
            )

            puts JSON.dump(
              tree_index: tree.index,
              branch_id: branch.id,
              entry_id: entry.id
            )
          RUBY

          new_branch = head_branch_row(services, setup.fetch('dst_dip_id'))
          new_tree_path = [
            backup_pool_fs,
            setup.fetch('dataset_full_name'),
            "tree.#{shared.fetch('tree_index')}"
          ].join('/')
          new_branch_path = branch_dataset_path(
            backup_pool_fs,
            setup.fetch('dataset_full_name'),
            new_branch
          )

          node2.succeeds("zfs create #{Shellwords.escape(new_tree_path)}", timeout: 60)
          node2.succeeds(
            "zfs send #{Shellwords.escape("#{old_branch_path}@#{snap1.fetch('name')}")} | " \
              "zfs recv #{Shellwords.escape(new_branch_path)}",
            timeout: 300
          )

          prune = destroy_snapshot_in_pool(
            services,
            admin_user_id: admin_user_id,
            sip_id: shared_sip_id
          )
          prune_state = services.mariadb_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{prune.fetch('chain_id')}"
          ).to_i
          entries_after_prune = branch_entries_for_dip(services, setup.fetch('dst_dip_id')).select do |row|
            row.fetch('snapshot_name') == snap1.fetch('name')
          end

          expect(prune_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            prune.fetch('chain_id')
          ).inspect
          expect(snapshot_rows_for_dip(services, setup.fetch('dst_dip_id')).map { |row| row.fetch('name') }).to include(
            snap1.fetch('name')
          )
          expect(entries_after_prune.map { |row| row.fetch('branch_id') }).to eq([shared.fetch('branch_id')])
          expect(node2.zfs_exists?("#{new_branch_path}@#{snap1.fetch('name')}", type: 'snapshot', timeout: 30)).to be(true)

          snap3 = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'shared-prune-s3'
          )
          backup = fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id')
          )
          handles = chain_transactions(services, backup.fetch('chain_id')).map { |row| row.fetch('handle') }
          backup_names = wait_for_snapshot_names(
            services,
            dip_id: setup.fetch('dst_dip_id'),
            include_names: [snap3.fetch('name')]
          )

          expect(handles).to include(
            tx_types(services).fetch('send'),
            tx_types(services).fetch('recv'),
            tx_types(services).fetch('recv_check')
          )
          expect(handles).not_to include(tx_types(services).fetch('create_tree'))
          expect(handles).not_to include(tx_types(services).fetch('branch_dataset'))
          expect(backup_names).to include(snap3.fetch('name'))
        end
      end
    '';
  }
)
