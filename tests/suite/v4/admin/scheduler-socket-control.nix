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
    name = "admin-scheduler-socket-control";

    description = ''
      Control the scheduler through its UNIX socket, reload repeatable tasks,
      and run a real group-snapshot task.
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
        services.wait_for_service('vpsadmin-scheduler.service')
      end

      describe 'scheduler socket control', order: :defined do
        it 'reloads and runs a registered group-snapshot task' do
          initial_status = scheduler_status(services)
          expect(initial_status.fetch('task_count')).to be >= 0

          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'admin-scheduler-primary',
            filesystem: primary_pool_fs,
            role: 'primary'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          dataset = create_top_level_dataset(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool.fetch('id'),
            dataset_name: 'admin-scheduler'
          )
          plan_name = 'admin_scheduler_' + SecureRandom.hex(4)

          registered = register_group_snapshot_plan_via_api_ruby(
            services,
            dataset_in_pool_id: dataset.fetch('dataset_in_pool_id'),
            plan_name: plan_name
          )
          task_id = Integer(registered.fetch('repeatable_task_id'))

          expect(scheduler_update(services).fetch('status')).to be(true)

          wait_until_block_succeeds(name: "scheduler task #{task_id} loaded") do
            tasks = scheduler_tasks(services)
            task_ids = tasks.map { |task| Integer(task.fetch('id')) }

            expect(task_ids).to include(task_id)
            expect(scheduler_status(services).fetch('task_count')).to be >= 1
          end

          before_count = dataset_snapshot_count(
            services,
            dataset_id: dataset.fetch('dataset_id')
          )
          run_response = scheduler_run_task(services, task_id: task_id)

          expect(run_response.fetch('status')).to be(true)

          wait_until_block_succeeds(name: "scheduler task #{task_id} created a snapshot") do
            count = dataset_snapshot_count(
              services,
              dataset_id: dataset.fetch('dataset_id')
            )

            expect(count).to be > before_count
          end

          unregister_group_snapshot_plan_via_api_ruby(
            services,
            dataset_in_pool_id: dataset.fetch('dataset_in_pool_id'),
            plan_name: plan_name
          )
          expect(scheduler_update(services).fetch('status')).to be(true)

          wait_until_block_succeeds(name: "scheduler task #{task_id} removed") do
            task_ids = scheduler_tasks(services).map { |task| Integer(task.fetch('id')) }

            expect(task_ids).not_to include(task_id)
          end
        end
      end
    '';
  }
)
