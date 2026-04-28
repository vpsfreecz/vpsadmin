import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
    };
  in
  {
    name = "tasks-dataset-expansion-enforce-and-resolve";

    description = ''
      Enforce an over-quota dataset expansion through the rake task and then
      resolve it with the shrink task.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "tasks"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        setup_tasks_cluster(services, node, pool_label: 'tasks-expansion')
      end

      describe 'dataset expansion enforcement tasks', order: :defined do
        it 'stops an over-quota VPS and shrinks the dataset after usage drops' do
          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'tasks-expansion',
            start: false
          )
          start_vps(services, vps.fetch('id'))
          wait_for_vps_on_node(
            services,
            vps_id: vps.fetch('id'),
            node_id: node1_id,
            running: true
          )
          set_vps_current_status_for_task(
            services,
            vps_id: vps.fetch('id'),
            running: true,
            uptime: 7200
          )
          info = dataset_info(services, vps.fetch('id'))
          original_refquota = info.fetch('refquota')
          expansion = create_dataset_expansion(
            services,
            admin_user_id: admin_user_id,
            dataset_id: info.fetch('dataset_id'),
            added_space: 1024,
            enable_notifications: false,
            enable_shrink: true,
            stop_vps: true,
            max_over_refquota_seconds: 0
          )
          expect_chain_done(
            services,
            expansion,
            label: 'seed dataset expansion',
            expected_handles: [storage_tx_types(services).fetch('storage_set_dataset')]
          )

          set_dataset_referenced_for_task(
            services,
            dataset_id: info.fetch('dataset_id'),
            value: original_refquota + 10
          )
          set_vps_current_status_for_task(
            services,
            vps_id: vps.fetch('id'),
            running: true,
            uptime: 7200
          )
          before_stop = max_transaction_chain_id(services)
          run_api_rake_task(
            services,
            task: 'vpsadmin:dataset_expansion:enforce',
            env: {
              MAX_EXPANSIONS: -1,
              OVERQUOTA_MB: 1,
              COOLDOWN: 0
            },
            timeout: 600
          )
          wait_for_chain_after(
            services,
            before_id: before_stop,
            type: 'TransactionChains::Vps::StopOverQuota',
            label: 'stop over quota'
          )
          wait_for_vps_on_node(
            services,
            vps_id: vps.fetch('id'),
            node_id: node1_id,
            running: false
          )

          set_dataset_referenced_for_task(
            services,
            dataset_id: info.fetch('dataset_id'),
            value: 0
          )
          before_shrink = max_transaction_chain_id(services)
          run_api_rake_task(
            services,
            task: 'vpsadmin:dataset_expansion:resolve',
            env: {
              COOLDOWN: 0,
              FREE_MB: 1,
              FREE_PERCENT: 5
            },
            timeout: 600
          )
          wait_for_chain_after(
            services,
            before_id: before_shrink,
            type: 'TransactionChains::Vps::ShrinkDataset',
            label: 'shrink expanded dataset'
          )

          dip = dataset_in_pool_row(services, info.fetch('dataset_in_pool_id'))
          expansion_row = dataset_expansion_row(services, expansion.fetch('dataset_expansion_id'))
          expect(dip.fetch('refquota')).to eq(original_refquota)
          expect(expansion_row.fetch('state')).to eq('resolved')
        end
      end
    '';
  }
)
