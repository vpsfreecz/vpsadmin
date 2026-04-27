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
    name = "vps-migrate-with-open-maintenance-window";

    description = ''
      Migrate a running VPS while it is inside an open maintenance window and
      verify the maintenance-window transactions are present in the chain.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      def set_today_fully_open_window(services, vps_id)
        services.api_ruby_json(code: <<~RUBY)
          vps = Vps.find(#{Integer(vps_id)})
          today = Time.now.wday

          VpsMaintenanceWindow.where(vps: vps).delete_all

          7.times do |weekday|
            window = VpsMaintenanceWindow.new(
              vps: vps,
              weekday: weekday,
              is_open: weekday == today,
              opens_at: weekday == today ? 0 : nil,
              closes_at: weekday == today ? 24 * 60 : nil
            )
            window.save!(validate: false)
          end

          puts JSON.dump(ok: true, weekday: today)
        RUBY
      end

      describe 'VPS migration in an open maintenance window', order: :defined do
        it 'migrates to node2 and includes maintenance-window transactions' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'mw-migrate-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'mw-migrate-dst',
            filesystem: 'tank/ct-mw-dst',
            role: 'hypervisor'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))
          wait_for_pool_online(services, dst_pool.fetch('id'))
          generate_migration_keys(services)

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-migrate-mw',
            start: false
          )
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: false)
          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s], timeout: 900)
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)
          set_today_fully_open_window(services, vps.fetch('id'))

          info = dataset_info(services, vps.fetch('id'))
          src_dataset_path = find_dataset_path_on_node(node1, info.fetch('dataset_full_name'))
          write_dataset_text(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/maintenance-window.txt',
            content: "maintenance window migration sentinel\n"
          )

          _, output = services.vpsadminctl.succeeds(
            args: ['vps', 'migrate', vps.fetch('id').to_s],
            parameters: {
              node: node2_id,
              maintenance_window: true,
              send_mail: false
            },
            timeout: 900
          )
          chain_id = action_state_id(output)
          expect(chain_id).not_to be_nil

          final_state = wait_for_chain_states_local(services, chain_id, %i[done failed fatal resolved], timeout: 900)
          failure_details = chain_failure_details(services, chain_id)
          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), failure_details.inspect

          handles = chain_transactions(services, chain_id).map { |row| row.fetch('handle') }
          expect(handles).to include(
            tx_types(services).fetch('maintenance_window_wait'),
            tx_types(services).fetch('maintenance_window_in_or_fail')
          )

          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node2_id, running: true)
          dst_dataset_path = find_dataset_path_on_node(node2, info.fetch('dataset_full_name'))
          expect(read_dataset_text(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'root/maintenance-window.txt'
          )).to include('maintenance window migration sentinel')
        end
      end
    '';
  }
)
