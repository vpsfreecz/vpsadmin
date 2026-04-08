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
    name = "vps-mount-lifecycle";

    description = ''
      Create, disable, re-enable, update, and destroy a regular VPS subdataset
      mount while checking both runtime visibility and DB state.
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

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'mount lifecycle', order: :defined do
        it 'creates, updates, and destroys a regular subdataset mount end to end' do
          host_payload_relative_path = 'private/payload.txt'

          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-mount-lifecycle',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-mount-lifecycle'
          )

          root_info = nil
          wait_until_block_succeeds(name: "dataset info available for VPS #{vps.fetch('id')}") do
            root_info = dataset_info(services, vps.fetch('id'))
            !root_info.nil?
          end

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: root_info.fetch('dataset_id'),
            name: 'mount-child',
            pool_fs: primary_pool_fs
          )

          create_response = create_vps_mount(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            dataset_id: child.fetch('dataset_id'),
            mountpoint: '/mnt/lifecycle'
          )
          create_audit, = expect_chain_done(
            services,
            create_response,
            label: 'mount-create',
            expected_handles: [
              tx_types(services).fetch('vps_mounts'),
              tx_types(services).fetch('vps_mount')
            ]
          )

          wait_until_block_succeeds(name: "mount visible in VPS #{vps.fetch('id')}") do
            vps_exec(
              node,
              vps_id: vps.fetch('id'),
              command: "printf 'mount-lifecycle-sentinel\n' > /mnt/lifecycle/payload.txt",
              timeout: 120
            )
            read_dataset_text(
              node,
              dataset_path: child.fetch('dataset_path'),
              relative_path: host_payload_relative_path
            ).include?('mount-lifecycle-sentinel')
          end

          disable_response = update_vps_mount(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            mount_id: create_response.fetch('mount_id'),
            attrs: { enabled: false }
          )
          disable_audit, = expect_chain_done(
            services,
            disable_response,
            label: 'mount-disable',
            expected_handles: [
              tx_types(services).fetch('vps_mounts'),
              tx_types(services).fetch('vps_umount')
            ]
          )

          wait_until_block_succeeds(name: "mount hidden in VPS #{vps.fetch('id')}") do
            node.fails(
              "osctl ct exec #{Integer(vps.fetch('id'))} sh -c " \
              "#{Shellwords.escape('test -f /mnt/lifecycle/payload.txt')}",
              timeout: 60
            )
            true
          end

          enable_response = update_vps_mount(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            mount_id: create_response.fetch('mount_id'),
            attrs: { enabled: true }
          )
          enable_audit, = expect_chain_done(
            services,
            enable_response,
            label: 'mount-enable',
            expected_handles: [
              tx_types(services).fetch('vps_mounts'),
              tx_types(services).fetch('vps_mount')
            ]
          )

          payload = nil
          wait_until_block_succeeds(name: "mount restored in VPS #{vps.fetch('id')}") do
            _, payload = vps_exec(
              node,
              vps_id: vps.fetch('id'),
              command: 'cat /mnt/lifecycle/payload.txt',
              timeout: 120
            )
            payload.include?('mount-lifecycle-sentinel')
          end

          on_start_fail_response = update_vps_mount(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            mount_id: create_response.fetch('mount_id'),
            attrs: { on_start_fail: 'fail_start' }
          )
          on_start_fail_audit, = expect_chain_done(
            services,
            on_start_fail_response,
            label: 'mount-on-start-fail',
            expected_handles: [tx_types(services).fetch('vps_mounts')]
          )

          mount_row = vps_mount_rows(services, vps.fetch('id')).detect do |row|
            row.fetch('id') == create_response.fetch('mount_id')
          end

          expect(read_dataset_text(
            node,
            dataset_path: child.fetch('dataset_path'),
            relative_path: host_payload_relative_path
          )).to include('mount-lifecycle-sentinel'), create_audit.inspect
          expect(payload).to include('mount-lifecycle-sentinel'), enable_audit.inspect
          expect(mount_row.fetch('on_start_fail')).to eq('fail_start'), on_start_fail_audit.inspect

          destroy_response = destroy_vps_mount(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            mount_id: create_response.fetch('mount_id')
          )
          destroy_audit, = expect_chain_done(
            services,
            destroy_response,
            label: 'mount-destroy',
            expected_handles: [
              tx_types(services).fetch('vps_mounts'),
              tx_types(services).fetch('vps_umount')
            ]
          )

          wait_until_block_succeeds(name: "mount removed from VPS #{vps.fetch('id')}") do
            node.fails(
              "osctl ct exec #{Integer(vps.fetch('id'))} sh -c " \
              "#{Shellwords.escape('test -f /mnt/lifecycle/payload.txt')}",
              timeout: 60
            )
            vps_mount_rows(services, vps.fetch('id')).empty?
          end

          expect(vps_mount_rows(services, vps.fetch('id'))).to eq([]), destroy_audit.inspect
          expect(disable_audit.fetch(:final_state)).not_to be_nil
        end
      end
    '';
  }
)
