import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
    };
  in
  {
    name = "admin-remote-mount-state";

    description = ''
      Send remote mount_state commands through nodectld and verify supervisor
      updates the mount row.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "admin"
    ];

    machines = import ../../machines/cluster/1-node.nix args;

    testScript = common + ''
      before(:suite) do
        setup_admin_cluster(services, node)
      end

      describe 'remote mount_state RPC', order: :defined do
        it 'updates mount state through supervisor ingestion' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'admin-remote-mount-state',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'admin-remote-mount-state'
          )
          wait_for_vps_on_node(
            services,
            vps_id: vps.fetch('id'),
            node_id: node1_id,
            running: true
          )

          root_info = dataset_info(services, vps.fetch('id'))
          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: root_info.fetch('dataset_id'),
            name: 'mount-state-child',
            pool_fs: primary_pool_fs
          )
          mount = create_vps_mount(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            dataset_id: child.fetch('dataset_id'),
            mountpoint: '/mnt/admin-state'
          )
          mount_id = mount.fetch('mount_id')

          [
            ['delayed', 4],
            ['mounted', 1]
          ].each do |state, expected|
            response = nodectl_remote_json(
              node,
              command: :mount_state,
              params: {
                vps_id: vps.fetch('id'),
                mount_id: mount_id,
                state: state
              }
            )

            expect(response.fetch('status')).to eq('ok')

            wait_until_block_succeeds(name: "mount #{mount_id} state #{state}") do
              row = vps_mount_state_row(services, mount_id: mount_id)
              row && Integer(row.fetch('current_state')) == expected
            end
          end
        end
      end
    '';
  }
)
