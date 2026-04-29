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
    name = "admin-dataset-plan-lifecycle";

    description = ''
      Register and unregister a temporary group-snapshot dataset plan and
      verify the control-plane rows are created and removed.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "admin"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      before(:suite) do
        setup_admin_cluster(services, node)
      end

      describe 'dataset plan lifecycle', order: :defined do
        it 'creates and removes group-snapshot plan side effects' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'admin-dataset-plan-primary',
            filesystem: primary_pool_fs,
            role: 'primary'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          dataset = create_top_level_dataset(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool.fetch('id'),
            dataset_name: 'admin-dataset-plan'
          )
          plan_name = 'admin_plan_' + SecureRandom.hex(4)

          registered = register_group_snapshot_plan_via_api_ruby(
            services,
            dataset_in_pool_id: dataset.fetch('dataset_in_pool_id'),
            plan_name: plan_name
          )
          state = dataset_plan_state(
            services,
            dataset_in_pool_id: dataset.fetch('dataset_in_pool_id'),
            plan_name: plan_name
          )

          expect(registered.fetch('dataset_in_pool_plan_id')).not_to be_nil
          expect(registered.fetch('dataset_action_id')).not_to be_nil
          expect(registered.fetch('repeatable_task_id')).not_to be_nil
          expect(registered.fetch('group_snapshot_id')).not_to be_nil
          expect(state.fetch('dataset_in_pool_plan_count')).to eq(1)
          expect(state.fetch('dataset_action_count')).to eq(1)
          expect(state.fetch('repeatable_task_count')).to eq(1)
          expect(state.fetch('group_snapshot_count')).to eq(1)

          unregister_group_snapshot_plan_via_api_ruby(
            services,
            dataset_in_pool_id: dataset.fetch('dataset_in_pool_id'),
            plan_name: plan_name
          )
          state = dataset_plan_state(
            services,
            dataset_in_pool_id: dataset.fetch('dataset_in_pool_id'),
            plan_name: plan_name
          )

          expect(state.fetch('dataset_in_pool_plan_count')).to eq(0)
          expect(state.fetch('dataset_action_count')).to eq(0)
          expect(state.fetch('repeatable_task_count')).to eq(0)
          expect(state.fetch('group_snapshot_count')).to eq(0)
        end
      end
    '';
  }
)
