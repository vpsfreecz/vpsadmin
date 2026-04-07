import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ../storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };
  in
  {
    name = "vps-reinstall";

    description = ''
      Reinstall a running VPS, remove pre-reinstall snapshots, and verify that
      the old rootfs contents are gone after the reinstall completes.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      def expect_vps_chain_done(services, response, label:, expected_handles: [])
        final_state = wait_for_vps_chain_done(services, response.fetch('chain_id'))
        handles = chain_transactions(services, response.fetch('chain_id')).map { |row| row.fetch('handle') }
        audit = {
          chain_id: response.fetch('chain_id'),
          final_state: final_state,
          handles: handles,
          failure_details: chain_failure_details(services, response.fetch('chain_id'))
        }

        expect(final_state).to eq(services.class::CHAIN_STATES[:done]), "#{label}: #{audit.inspect}"

        expected_handles.each do |handle|
          expect(handles).to include(handle), "#{label}: #{audit.inspect}"
        end

        audit
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'reinstall', order: :defined do
        it 'removes local snapshots, advances dataset history, and replaces the previous rootfs' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-reinstall-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-reinstall'
          )

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          dataset = dataset_info(services, vps.fetch('id'))
          history_before = services.mysql_scalar(sql: <<~SQL).to_i
            SELECT current_history_id
            FROM datasets
            WHERE id = #{Integer(dataset.fetch('dataset_id'))}
          SQL

          vps_exec(
            node,
            vps_id: vps.fetch('id'),
            command: "printf 'before reinstall\\n' > /root/before-reinstall.txt && printf 'secondary sentinel\\n' > /root/before-reinstall-2.txt",
            timeout: 120
          )

          create_snapshot(
            services,
            dataset_id: dataset.fetch('dataset_id'),
            dip_id: dataset.fetch('dataset_in_pool_id'),
            label: 'before-reinstall-a'
          )
          create_snapshot(
            services,
            dataset_id: dataset.fetch('dataset_id'),
            dip_id: dataset.fetch('dataset_in_pool_id'),
            label: 'before-reinstall-b'
          )

          response = vps_reinstall(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            os_template_id: 2
          )
          audit = expect_vps_chain_done(
            services,
            response,
            label: 'reinstall',
            expected_handles: [
              tx_types(services).fetch('vps_stop'),
              tx_types(services).fetch('vps_reinstall')
            ]
          )

          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          snapshots_after = snapshot_rows_for_dip(services, dataset.fetch('dataset_in_pool_id'))
          history_after = services.mysql_scalar(sql: <<~SQL).to_i
            SELECT current_history_id
            FROM datasets
            WHERE id = #{Integer(dataset.fetch('dataset_id'))}
          SQL

          expect(snapshots_after).to eq([]), audit.inspect
          expect(history_after).to be > history_before

          wait_until_block_succeeds(name: "reinstalled VPS #{vps.fetch('id')} has replaced rootfs") do
            node.fails(
              "osctl ct exec #{Integer(vps.fetch('id'))} sh -c #{Shellwords.escape('test -e /root/before-reinstall.txt')}",
              timeout: 60
            )
            node.fails(
              "osctl ct exec #{Integer(vps.fetch('id'))} sh -c #{Shellwords.escape('test -e /root/before-reinstall-2.txt')}",
              timeout: 60
            )
            true
          end
        end
      end
    '';
  }
)
