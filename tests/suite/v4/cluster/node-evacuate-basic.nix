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
    name = "node-evacuate-basic";

    description = ''
      Evacuate a node with two running VPSes and verify the migration plan
      completes, releases its lock, and moves both VPSes to the target node.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "cluster"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      def run_migration_plan_until_done(services, plan_id, timeout: 900)
        wait_until_block_succeeds(name: "migration plan #{plan_id} done", timeout: timeout) do
          services.run_vps_migration_task(timeout: 300)
          expect(services.migration_plan_row(plan_id).fetch('state')).to eq('done')
          true
        end

        services.migration_plan_row(plan_id)
      end

      def migration_plan_id(output)
        output['migration_plan_id'] || output.dig('node', 'migration_plan_id') ||
          output.dig('response', 'migration_plan_id')
      end

      describe 'node evacuation', order: :defined do
        it 'migrates all VPSes off the source node' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'evacuate-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'evacuate-dst',
            filesystem: 'tank/ct-evacuate-dst',
            role: 'hypervisor'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))
          wait_for_pool_online(services, dst_pool.fetch('id'))
          generate_migration_keys(services)

          vpses = 2.times.map do |index|
            vps = create_vps(
              services,
              admin_user_id: admin_user_id,
              node_id: node1_id,
              hostname: "evacuate-basic-#{index}",
              start: false
            )
            wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: false)
            services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s], timeout: 900)
            wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

            info = dataset_info(services, vps.fetch('id'))
            dataset_path = find_dataset_path_on_node(node1, info.fetch('dataset_full_name'))
            write_dataset_text(
              node1,
              dataset_path: dataset_path,
              relative_path: "root/evacuate-#{index}.txt",
              content: "evacuation sentinel #{index}\n"
            )

            vps.merge('dataset_info' => info, 'sentinel_path' => "root/evacuate-#{index}.txt")
          end

          _, output = services.vpsadminctl.succeeds(
            args: ['node', 'evacuate', node1_id.to_s],
            parameters: {
              dst_node: node2_id,
              concurrency: 2,
              maintenance_window: false,
              cleanup_data: true,
              send_mail: false
            },
            timeout: 900
          )
          plan_id = migration_plan_id(output)

          plan = run_migration_plan_until_done(services, plan_id)
          expect(plan.fetch('state')).to eq('done')
          expect(plan.fetch('lock_count')).to eq(0)

          rows = services.vps_migration_rows(plan_id)
          expect(rows.map { |row| row.fetch('state') }).to all(eq('done'))

          vpses.each_with_index do |vps, index|
            wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node2_id, running: true)
            dst_dataset_path = find_dataset_path_on_node(
              node2,
              vps.fetch('dataset_info').fetch('dataset_full_name')
            )
            expect(read_dataset_text(
              node2,
              dataset_path: dst_dataset_path,
              relative_path: vps.fetch('sentinel_path')
            )).to include("evacuation sentinel #{index}")
          end
        end
      end
    '';
  }
)
