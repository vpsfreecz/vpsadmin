import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-2-node.nix;
    node1Seed = clusterSeed.nodes.node1;
    node2Seed = clusterSeed.nodes.node2;
    common = import ../storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = node1Seed.id;
      node2Id = node2Seed.id;
    };
  in
  {
    name = "vps-migrate-with-descendants";

    description = ''
      Migrate a VPS with descendant datasets and verify both the root dataset
      and descendant data are present on the destination node afterwards.
    '';

    tags = [
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'VPS migration with descendant datasets', order: :defined do
        it 'moves the root dataset together with its descendants' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-desc-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-desc'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-desc-dst',
            filesystem: dst_pool_fs,
            role: 'hypervisor'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))
          wait_for_pool_online(services, dst_pool.fetch('id'))
          generate_migration_keys(services)

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-migrate-desc'
          )

          info = nil
          wait_until_block_succeeds(name: "dataset info available for VPS #{vps.fetch('id')}") do
            info = dataset_info(services, vps.fetch('id'))
            !info.nil?
          end

          _, vps_row = services.vpsadminctl.succeeds(args: ['vps', 'show', vps.fetch('id').to_s])
          unless vps_row.fetch('vps').fetch('is_running')
            services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          end
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: info.fetch('dataset_id'),
            name: 'var',
            pool_fs: primary_pool_fs
          )
          grandchild = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: child.fetch('dataset_id'),
            name: 'log',
            pool_fs: primary_pool_fs
          )

          src_dataset_path = find_dataset_path_on_node(node1, info.fetch('dataset_full_name'))

          write_dataset_text(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/root.txt',
            content: "root data\n"
          )
          write_dataset_text(
            node1,
            dataset_path: child.fetch('dataset_path'),
            relative_path: 'files/child.txt',
            content: "child data\n"
          )
          write_dataset_text(
            node1,
            dataset_path: grandchild.fetch('dataset_path'),
            relative_path: 'files/grandchild.txt',
            content: "grandchild data\n"
          )

          response = vps_migrate(
            services,
            vps_id: vps.fetch('id'),
            node_id: node2_id,
            send_mail: false
          )
          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            response.fetch('chain_id')
          ).inspect

          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node2_id, running: true)
          dst_dataset_path = find_dataset_path_on_node(node2, info.fetch('dataset_full_name'))
          dst_child_path = find_dataset_path_on_node(node2, child.fetch('full_name'))
          dst_grandchild_path = find_dataset_path_on_node(node2, grandchild.fetch('full_name'))
          expect(read_dataset_text(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'root/root.txt'
          )).to include('root data')
          expect(read_dataset_text(
            node2,
            dataset_path: dst_child_path,
            relative_path: 'files/child.txt'
          )).to include('child data')
          expect(read_dataset_text(
            node2,
            dataset_path: dst_grandchild_path,
            relative_path: 'files/grandchild.txt'
          )).to include('grandchild data')
        end
      end
    '';
  }
)
