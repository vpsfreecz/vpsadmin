import ../../../make-test.nix (
  { ... }@args:
  let
    seed = import ../../../../api/db/seeds/test-2-node.nix;
    common = import ../storage/remote-common.nix {
      adminUserId = seed.adminUser.id;
      node1Id = seed.nodes.node1.id;
      node2Id = seed.nodes.node2.id;
    };
  in
  {
    name = "node-evacuate-concurrency";

    description = ''
      Evacuate a node with concurrency one and verify queued migrations are
      started in order only after the migration task is run again.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "cluster"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      def migration_plan_id(output)
        output['migration_plan_id'] || output.dig('node', 'migration_plan_id') ||
          output.dig('response', 'migration_plan_id')
      end

      def expect_migration_states(rows, states)
        expect(rows.map { |row| row.fetch('state') }).to eq(states)
        expect(rows.count { |row| row.fetch('state') == 'running' }).to be <= 1
      end

      def wait_for_running_chain_done(services, row)
        services.wait_for_chain_state(row.fetch('chain_id'), state: :done, timeout: 900)
      end

      describe 'node evacuation concurrency', order: :defined do
        it 'honors plan concurrency and starts queued migrations in order' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'evacuate-concurrency-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'evacuate-concurrency-dst',
            filesystem: 'tank/ct-evacuate-concurrency-dst',
            role: 'hypervisor'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))
          wait_for_pool_online(services, dst_pool.fetch('id'))
          generate_migration_keys(services)

          vpses = 3.times.map do |index|
            vps = create_vps(
              services,
              admin_user_id: admin_user_id,
              node_id: node1_id,
              hostname: "evacuate-concurrency-#{index}",
              start: false
            )
            wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: false)
            services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s], timeout: 900)
            wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)
            vps
          end
          vps_ids = vpses.map { |vps| vps.fetch('id') }

          node1.succeeds('nodectl queue pause zfs_send')
          node1.succeeds('nodectl queue pause zfs_recv')
          node2.succeeds('nodectl queue pause zfs_send')
          node2.succeeds('nodectl queue pause zfs_recv')

          _, output = services.vpsadminctl.succeeds(
            args: ['node', 'evacuate', node1_id.to_s],
            parameters: {
              dst_node: node2_id,
              concurrency: 1,
              maintenance_window: false,
              cleanup_data: true,
              send_mail: false
            },
            timeout: 900
          )
          plan_id = migration_plan_id(output)

          expect(services.migration_plan_row(plan_id).fetch('state')).to eq('running')
          rows = services.vps_migration_rows(plan_id)
          expect(rows.map { |row| row.fetch('vps_id') }).to eq(vps_ids)
          expect_migration_states(rows, %w[running queued queued])
          first_running = rows.fetch(0)

          node1.succeeds('nodectl queue resume all', timeout: 60)
          node2.succeeds('nodectl queue resume all', timeout: 60)

          wait_for_running_chain_done(services, first_running)
          services.run_vps_migration_task(timeout: 300)
          rows = services.vps_migration_rows(plan_id)
          expect_migration_states(rows, %w[done running queued])
          expect(rows.fetch(1).fetch('vps_id')).to eq(vps_ids.fetch(1))

          wait_for_running_chain_done(services, rows.fetch(1))
          services.run_vps_migration_task(timeout: 300)
          rows = services.vps_migration_rows(plan_id)
          expect_migration_states(rows, %w[done done running])
          expect(rows.fetch(2).fetch('vps_id')).to eq(vps_ids.fetch(2))

          wait_for_running_chain_done(services, rows.fetch(2))
          services.run_vps_migration_task(timeout: 300)

          plan = services.wait_for_migration_plan_state(plan_id, state: :done, timeout: 300)
          expect(plan.fetch('lock_count')).to eq(0)
          rows = services.vps_migration_rows(plan_id)
          expect_migration_states(rows, %w[done done done])

          vps_ids.each do |vps_id|
            wait_for_vps_on_node(services, vps_id: vps_id, node_id: node2_id, running: true)
          end
        ensure
          node1.succeeds('nodectl queue resume all', timeout: 60) if defined?(node1)
          node2.succeeds('nodectl queue resume all', timeout: 60) if defined?(node2)
        end
      end
    '';
  }
)
