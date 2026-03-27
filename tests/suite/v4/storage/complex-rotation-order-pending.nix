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
    name = "storage-complex-rotation-order-pending";

    description = ''
      Build a complex multi-tree remote backup topology, run aggressive
      rotation, and keep the desired dependency-safe rotation behaviour as a
      real pending contract.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'rotating a complex multi-tree backup topology', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-complex-rotation',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'keeps a pending contract for dependency-safe aggressive rotation across tree switches' do
          build_complex_multi_tree_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            vps_id: @setup.fetch('vps_id'),
            label_prefix: 'complex-rotation'
          )

          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'complex-rotation-s11'
          )
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'complex-rotation-s12'
          )

          storage_types = storage_tx_types(services)
          count_before = snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id')).count
          branch_count_before = branch_rows_for_dip(services, @setup.fetch('dst_dip_id')).count
          report_before = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          )
          diagnostic_before = delete_order_diagnostic(report_before)
          leaf_contract_before = delete_order_leaf_contract(report_before)
          tree_count_before = report_before.fetch('db').fetch('trees').count
          puts JSON.pretty_generate(
            'case' => 'complex-rotation-order-pending',
            'stage' => 'before-rotation',
            'diagnostic' => diagnostic_before,
            'leaf_contract' => leaf_contract_before
          )
          maybe_capture_topology_fixture(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path'),
            file_name: 'complex-rotation-before.json',
            metadata: {
              'case' => 'complex-rotation-order-pending',
              'expected_leaf_sets_match' => leaf_contract_before.fetch('leaf_sets_match')
            }
          )

          set_snapshot_retention(
            services,
            dip_id: @setup.fetch('dst_dip_id'),
            min_snapshots: 0,
            max_snapshots: 0,
            snapshot_max_age: 0
          )

          failed_chain_ids = []
          final_states = {}
          empty_rotations = []
          failure_details = {}
          dependency_failures = {}
          unexpected_failures = {}

          8.times do
            rotation = rotate_dataset(
              services,
              admin_user_id: admin_user_id,
              dip_id: @setup.fetch('dst_dip_id')
            )
            if rotation.fetch('empty', false)
              empty_rotations << rotation
              next
            end

            final_state = wait_for_chain_states_local(
              services,
              rotation.fetch('chain_id'),
              %i[done failed fatal resolved]
            )
            final_states[rotation.fetch('chain_id')] = final_state

            next if final_state == services.class::CHAIN_STATES[:done]

            expect([
              services.class::CHAIN_STATES[:failed],
              services.class::CHAIN_STATES[:fatal],
              services.class::CHAIN_STATES[:resolved]
            ]).to include(final_state), final_states.inspect

            final_state = services.mysql_scalar(
              sql: "SELECT state FROM transaction_chains WHERE id = #{rotation.fetch('chain_id')}"
            ).to_i
            final_states[rotation.fetch('chain_id')] = final_state

            failed_chain_ids << rotation.fetch('chain_id')
            details = chain_failure_details(services, rotation.fetch('chain_id'))
            failure_details[rotation.fetch('chain_id')] = details
            dependency_failures[rotation.fetch('chain_id')] = details.select do |detail|
              dependency_failure?(detail)
            end
            unexpected_failures[rotation.fetch('chain_id')] = details.reject do |detail|
              dependency_failure?(detail)
            end
          end

          remaining = snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id')).map { |row| row.fetch('name') }
          branch_count_after = branch_rows_for_dip(services, @setup.fetch('dst_dip_id')).count
          report_after = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          )
          diagnostic_after = delete_order_diagnostic(report_after)
          leaf_contract_after = delete_order_leaf_contract(report_after)
          tree_count_after = report_after.fetch('db').fetch('trees').count
          puts JSON.pretty_generate(
            'case' => 'complex-rotation-order-pending',
            'stage' => 'after-rotation',
            'failed_chain_ids' => failed_chain_ids,
            'final_states' => final_states,
            'diagnostic' => diagnostic_after,
            'leaf_contract' => leaf_contract_after
          )
          maybe_capture_topology_fixture(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path'),
            file_name: 'complex-rotation-after.json',
            metadata: {
              'case' => 'complex-rotation-order-pending',
              'failed_chain_ids' => failed_chain_ids,
              'final_states' => final_states,
              'expected_leaf_sets_match' => leaf_contract_after.fetch('leaf_sets_match')
            }
          )
          failure_message = {
            diagnostic_before: diagnostic_before,
            diagnostic_after: diagnostic_after,
            leaf_contract_before: leaf_contract_before,
            leaf_contract_after: leaf_contract_after,
            empty_rotations: empty_rotations,
            final_states: final_states,
            failure_details: failure_details
          }.inspect

          pending 'complex repeated rollback + tree switching can strand old snapshots because metadata is not enough to derive safe rotation order'

          expect(diagnostic_before.fetch('db_but_not_zfs')).to eq([]), diagnostic_before.inspect
          expect(empty_rotations).to eq([]), failure_message

          failed_chain_ids.each do |chain_id|
            assert_dependency_failure_contract!(
              services,
              chain_id: chain_id,
              allowed_handles: [storage_types.fetch('destroy_snapshot')],
              report: report_before
            )
          end

          if failed_chain_ids.any?
            expect(leaf_contract_before.fetch('leaf_sets_match')).to be(false), failure_message
          end

          expect(leaf_contract_before.fetch('leaf_sets_match')).to be(true), leaf_contract_before.inspect
          expect(leaf_contract_after.fetch('leaf_sets_match')).to be(true), leaf_contract_after.inspect
          expect(dependency_failures.values.flatten).to eq([]), failure_message
          expect(unexpected_failures.values.flatten).to eq([]), failure_message
          expect(failed_chain_ids).to eq([]), failure_message
          expect(remaining.count).to be < count_before
          expect(branch_count_after).to be <= branch_count_before
          expect(tree_count_after).to be <= tree_count_before
        end
      end
    '';
  }
)
