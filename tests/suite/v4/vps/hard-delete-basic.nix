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
    name = "vps-hard-delete-basic";

    description = ''
      Hard-delete a VPS with a descendant dataset and verify the container,
      primary datasets, and DB-side runtime attachments are removed.
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

      describe 'basic hard delete', order: :defined do
        it 'removes the container, root dataset, descendant dataset, and DB references' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-hard-delete-basic',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-hard-delete-basic'
          )

          root_info = nil
          wait_until_block_succeeds(name: "dataset info available for VPS #{vps.fetch('id')}") do
            root_info = dataset_info(services, vps.fetch('id'))
            !root_info.nil?
          end

          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: root_info.fetch('dataset_id'),
            name: 'delete-child',
            pool_fs: primary_pool_fs
          )

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          root_dataset_path = "#{root_info.fetch('pool_filesystem')}/#{root_info.fetch('dataset_full_name')}"
          response = hard_delete_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id')
          )
          audit, = expect_chain_done(
            services,
            response,
            label: 'hard-delete-basic',
            expected_handles: [
              tx_types(services).fetch('vps_stop'),
              tx_types(services).fetch('vps_destroy')
            ]
          )

          wait_until_block_succeeds(name: "hard-deleted VPS #{vps.fetch('id')} removed from node and DB attachments") do
            node.fails("osctl ct show #{Integer(vps.fetch('id'))}", timeout: 60)
            !node.zfs_exists?(root_dataset_path, type: 'filesystem', timeout: 30) &&
              !node.zfs_exists?(child.fetch('dataset_path'), type: 'filesystem', timeout: 30) &&
              vps_network_interface_rows(services, vps.fetch('id')).empty? &&
              vps_mount_rows(services, vps.fetch('id')).empty?
          end

          vps_row = vps_unscoped_row(services, vps.fetch('id'))
          vps_lock_count = services.mysql_scalar(sql: <<~SQL).to_i
            SELECT COUNT(*)
            FROM resource_locks
            WHERE resource = 'Vps'
              AND row_id = #{Integer(vps.fetch('id'))}
          SQL

          expect(node.zfs_exists?(root_dataset_path, type: 'filesystem', timeout: 30)).to be(false), audit.inspect
          expect(node.zfs_exists?(child.fetch('dataset_path'), type: 'filesystem', timeout: 30)).to be(false), audit.inspect
          expect(vps_network_interface_rows(services, vps.fetch('id'))).to eq([]), audit.inspect
          expect(vps_mount_rows(services, vps.fetch('id'))).to eq([]), audit.inspect
          expect(vps_row.fetch('object_state')).to eq('hard_delete'), audit.inspect
          expect(vps_row.fetch('dataset_in_pool_id')).to be_nil, audit.inspect
          expect(vps_row.fetch('user_namespace_map_id')).to be_nil, audit.inspect
          expect(vps_lock_count).to eq(0), audit.inspect
          expect(chain_port_reservations(services, response.fetch('chain_id'))).to eq([]), audit.inspect
        end
      end
    '';
  }
)
