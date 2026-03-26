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
          report = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          )
          diagnostic = delete_order_diagnostic(report)
          leaf_contract = delete_order_leaf_contract(report)
          branches = report.fetch('db').fetch('branches')
          entries = report.fetch('db').fetch('entries')
          entry_ids = entries.map { |row| row.fetch('entry_id') }
          snapshot_names = entries.map { |row| row.fetch('snapshot_name') }.uniq
          zfs_refcounts = report.fetch('zfs').fetch('clones').each_with_object(Hash.new(0)) do |(path, clones), acc|
            acc[path.split('@', 2).last] += clones.count
          end
          db_refcounts = db_reference_counts_by_snapshot(entries)

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
          destroy_failures = chain_failure_details(services, response.fetch('chain_id'))
          dependency_failures = dependency_failure_details(services, response.fetch('chain_id'))
          failure_message = {
            diagnostic: diagnostic,
            leaf_contract: leaf_contract,
            destroy_failures: destroy_failures
          }.inspect

          pending 'multiple rollback branching can lose enough dependency information that delete ordering becomes unsafe'

          if final_state != services.class::CHAIN_STATES[:done]
            assert_known_dependency_failure!(
              services,
              chain_id: response.fetch('chain_id'),
              allowed_handles: [storage_types.fetch('destroy_snapshot')],
              diagnostic: leaf_contract
            )

            expect(leaf_contract.fetch('leaf_sets_match')).to be(false), {
              destroy_failures: destroy_failures,
              leaf_contract: leaf_contract
            }.inspect
          end

          branches.each do |branch|
            branch_path = branch_dataset_path(
              backup_pool_fs,
              @setup.fetch('dataset_full_name'),
              branch
            )
            origin = report.fetch('zfs').fetch('origins')[branch_path]

            next if origin.nil? || origin.empty? || origin == '-'

            expect(snapshot_names).to include(origin.split('@', 2).last), failure_message
          end

          entries.each do |entry|
            next if entry.fetch('parent_entry_id').nil?

            expect(entry_ids).to include(entry.fetch('parent_entry_id')), failure_message
          end

          expect(db_refcounts).to eq(zfs_refcounts), failure_message
          expect(leaf_contract.fetch('leaf_sets_match')).to be(true), leaf_contract.inspect
          expect(leaf_contract.fetch('db_but_not_zfs')).to eq([]), leaf_contract.inspect
          expect(leaf_contract.fetch('zfs_but_not_db')).to eq([]), leaf_contract.inspect

          expect(
            services.mysql_scalar(
              sql: "SELECT COUNT(*) FROM dataset_trees WHERE dataset_in_pool_id = #{@setup.fetch('dst_dip_id')} AND head = 1"
            )
          ).to eq('1'), failure_message

          branches.group_by { |row| row.fetch('tree_id') }.each_value do |tree_branches|
            expect(tree_branches.count { |row| row.fetch('head') == 1 }).to eq(1), failure_message
          end

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), destroy_failures.inspect
          expect(dependency_failures).to eq([]), destroy_failures.inspect
          expect(topology.fetch('snapshots').fetch('s8').fetch('name')).not_to be_nil
          expect(topology.fetch('snapshots').fetch('s8').fetch('name').to_s).not_to eq("")
        end
      end
    '';
  }
)
