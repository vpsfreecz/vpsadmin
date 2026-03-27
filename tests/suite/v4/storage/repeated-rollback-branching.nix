import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-2-node.nix;
    node1Seed = clusterSeed.nodes.node1;
    node2Seed = clusterSeed.nodes.node2;
    common = import ./remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = node1Seed.id;
      node2Id = node2Seed.id;
    };
  in
  {
    name = "storage-repeated-rollback-branching";

    description = ''
      Build a repeated remote rollback topology and compare backup dependency
      metadata against the real ZFS origin/clone state on the backup node. The
      core example is intentionally pending because the current metadata model
      can lose enough topology information to make delete ordering unsafe.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'repeated rollback branching', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-repeated-rollback',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'keeps DB dependency metadata aligned with ZFS after repeated rollback branching' do
          topology = build_repeated_rollback_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            vps_id: @setup.fetch('vps_id'),
            label_prefix: 'repeat-topology'
          )

          storage_types = storage_tx_types(services)
          report_before = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          )
          diagnostic_before = delete_order_diagnostic(report_before)
          leaf_contract_before = delete_order_leaf_contract(report_before)
          branches = report_before.fetch('db').fetch('branches')
          head_tree_count_before = report_before.fetch('db').fetch('trees').count do |tree|
            tree.fetch('head') == 1
          end
          entries = report_before.fetch('db').fetch('entries')
          entry_ids = entries.map { |row| row.fetch('entry_id') }
          snapshot_names = entries.map { |row| row.fetch('snapshot_name') }.uniq
          puts JSON.pretty_generate(
            'case' => 'repeated-rollback-branching',
            'stage' => 'before-destroy',
            'diagnostic' => diagnostic_before,
            'leaf_contract' => leaf_contract_before
          )

          maybe_capture_topology_fixture(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path'),
            file_name: 'repeated-rollback-before.json',
            metadata: {
              'case' => 'repeated-rollback-branching',
              'expected_leaf_sets_match' => leaf_contract_before.fetch('leaf_sets_match')
            }
          )

          response = destroy_backup_dataset(
            services,
            admin_user_id: admin_user_id,
            dip_id: @setup.fetch('dst_dip_id')
          )
          wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          final_state = services.mysql_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{response.fetch('chain_id')}"
          ).to_i
          backup_dataset_exists_after = backup_dataset_exists?(
            node2,
            @setup.fetch('backup_dataset_path')
          )
          dip_exists_after = services.mysql_scalar(
            sql: "SELECT COUNT(*) FROM dataset_in_pools WHERE id = #{@setup.fetch('dst_dip_id')}"
          ).to_i > 0
          tree_count_after = services.mysql_scalar(
            sql: "SELECT COUNT(*) FROM dataset_trees WHERE dataset_in_pool_id = #{@setup.fetch('dst_dip_id')}"
          ).to_i
          branch_count_after = services.mysql_scalar(
            sql: <<~SQL
              SELECT COUNT(*)
              FROM branches b
              INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
              WHERE t.dataset_in_pool_id = #{@setup.fetch('dst_dip_id')}
            SQL
          ).to_i
          entry_count_after = services.mysql_scalar(
            sql: <<~SQL
              SELECT COUNT(*)
              FROM snapshot_in_pool_in_branches e
              INNER JOIN branches b ON b.id = e.branch_id
              INNER JOIN dataset_trees t ON t.id = b.dataset_tree_id
              WHERE t.dataset_in_pool_id = #{@setup.fetch('dst_dip_id')}
            SQL
          ).to_i
          report_after =
            if backup_dataset_exists_after
              backup_topology_report(
                services,
                backup_node: node2,
                dst_dip_id: @setup.fetch('dst_dip_id'),
                backup_dataset_path: @setup.fetch('backup_dataset_path')
              )
            end
          diagnostic_after = report_after && delete_order_diagnostic(report_after)
          leaf_contract_after = report_after && delete_order_leaf_contract(report_after)
          puts JSON.pretty_generate(
            'case' => 'repeated-rollback-branching',
            'stage' => 'after-destroy',
            'chain_id' => response.fetch('chain_id'),
            'final_state' => final_state,
            'backup_dataset_exists_after' => backup_dataset_exists_after,
            'dip_exists_after' => dip_exists_after,
            'tree_count_after' => tree_count_after,
            'branch_count_after' => branch_count_after,
            'entry_count_after' => entry_count_after,
            'diagnostic' => diagnostic_after,
            'leaf_contract' => leaf_contract_after
          )
          if report_after
            maybe_capture_topology_fixture(
              services,
              backup_node: node2,
              dst_dip_id: @setup.fetch('dst_dip_id'),
              backup_dataset_path: @setup.fetch('backup_dataset_path'),
              file_name: 'repeated-rollback-after.json',
              metadata: {
                'case' => 'repeated-rollback-branching',
                'chain_id' => response.fetch('chain_id'),
                'final_state' => final_state,
                'expected_leaf_sets_match' => leaf_contract_after.fetch('leaf_sets_match')
              }
            )
          end
          destroy_failures = chain_failure_details(services, response.fetch('chain_id'))
          dependency_failures = dependency_failure_details(services, response.fetch('chain_id'))
          failure_message = {
            diagnostic_before: diagnostic_before,
            diagnostic_after: diagnostic_after,
            leaf_contract_before: leaf_contract_before,
            leaf_contract_after: leaf_contract_after,
            backup_dataset_exists_after: backup_dataset_exists_after,
            dip_exists_after: dip_exists_after,
            tree_count_after: tree_count_after,
            branch_count_after: branch_count_after,
            entry_count_after: entry_count_after,
            destroy_failures: destroy_failures
          }.inspect

          pending 'multiple rollback branching can lose enough dependency information that delete ordering becomes unsafe' if final_state != services.class::CHAIN_STATES[:done]

          if final_state != services.class::CHAIN_STATES[:done]
            expect([
              services.class::CHAIN_STATES[:failed],
              services.class::CHAIN_STATES[:fatal],
              services.class::CHAIN_STATES[:resolved]
            ]).to include(final_state), failure_message

            contract = assert_dependency_failure_contract!(
              services,
              chain_id: response.fetch('chain_id'),
              allowed_handles: [storage_types.fetch('destroy_snapshot')],
              report: report_before
            )

            expect(contract.fetch('leaf_sets_match')).to be(false), {
              destroy_failures: destroy_failures,
              leaf_contract_before: leaf_contract_before
            }.inspect
            expect(dependency_failures).not_to eq([]), failure_message
          end

          branches.each do |branch|
            branch_path = branch_dataset_path(
              backup_pool_fs,
              @setup.fetch('dataset_full_name'),
              branch
            )
            origin = report_before.fetch('zfs').fetch('origins')[branch_path]
            next if origin.nil? || origin.empty? || origin == '-'

            expect(snapshot_names).to include(origin.split('@', 2).last), failure_message
          end

          entries.each do |entry|
            next if entry.fetch('parent_entry_id').nil?

            expect(entry_ids).to include(entry.fetch('parent_entry_id')), failure_message
          end

          entries.each do |entry|
            dependent_count = entries.count do |candidate|
              candidate.fetch('parent_entry_id') == entry.fetch('entry_id')
            end

            expect(entry.fetch('reference_count')).to eq(dependent_count), {
              entry: entry,
              dependent_count: dependent_count,
              diagnostic_before: diagnostic_before
            }.inspect
          end

          expect(leaf_contract_before.fetch('leaf_sets_match')).to be(true), leaf_contract_before.inspect
          expect(leaf_contract_before.fetch('db_but_not_zfs')).to eq([]), leaf_contract_before.inspect
          expect(leaf_contract_before.fetch('zfs_but_not_db')).to eq([]), leaf_contract_before.inspect

          expect(head_tree_count_before).to eq(1), failure_message

          branches.group_by { |row| row.fetch('tree_id') }.each_value do |tree_branches|
            expect(tree_branches.count { |row| row.fetch('head') == 1 }).to eq(1), failure_message
          end

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), destroy_failures.inspect
          expect(backup_dataset_exists_after).to be(false), failure_message
          expect(dip_exists_after).to be(false), failure_message
          expect(tree_count_after).to eq(0), failure_message
          expect(branch_count_after).to eq(0), failure_message
          expect(entry_count_after).to eq(0), failure_message
          expect(dependency_failures).to eq([]), destroy_failures.inspect
          expect(topology.fetch('snapshots').fetch('s8').fetch('name')).not_to be_nil
          expect(topology.fetch('snapshots').fetch('s8').fetch('name').to_s).not_to eq("")
        end
      end
    '';
  }
)
