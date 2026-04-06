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
    name = "vps-clone-with-descendants-and-mounts";

    description = ''
      Clone a VPS with descendant datasets and a mounted subdataset, verify the
      descendant datasets exist on the clone, and confirm the mount was remapped.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote VPS clone with descendants and mounts', order: :defined do
        it 'copies descendant datasets and remaps descendant mounts to the clone' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-clone-desc-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-clone-desc'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-clone-desc-dst',
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
            hostname: 'vps-clone-desc'
          )

          src_info = nil
          wait_until_block_succeeds(name: "source dataset info for VPS #{vps.fetch('id')}") do
            src_info = dataset_info(services, vps.fetch('id'))
            !src_info.nil?
          end

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: src_info.fetch('dataset_id'),
            name: 'clone-desc-child',
            pool_fs: primary_pool_fs
          )
          services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}

            dip = DatasetInPool.find(#{Integer(child.fetch('dip_id'))})
            use = ClusterResourceUse.joins(user_cluster_resource: :cluster_resource).find_by!(
              class_name: 'DatasetInPool',
              table_name: 'dataset_in_pools',
              row_id: dip.id,
              cluster_resources: { name: 'diskspace' }
            )
            ClusterResourceUse.where(id: use.id).update_all(value: 128)

            puts JSON.dump(dip_id: dip.id)
          RUBY

          mount = create_vps_mount(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            dataset_id: child.fetch('dataset_id'),
            mountpoint: '/mnt/clone-desc'
          )

          src_root_path = find_dataset_path_on_node(node1, src_info.fetch('dataset_full_name'))
          write_dataset_text(
            node1,
            dataset_path: src_root_path,
            relative_path: 'root/root.txt',
            content: "clone descendant root sentinel\n"
          )
          write_dataset_text(
            node1,
            dataset_path: child.fetch('dataset_path'),
            relative_path: 'payload/child.txt',
            content: "clone descendant child sentinel\n"
          )

          response = vps_clone(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            node_id: node2_id,
            stop: false
          )
          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          chain_diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details
          }

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_diagnostic.inspect

          clone_info = nil
          wait_until_block_succeeds(name: "clone dataset info for VPS #{response.fetch('cloned_vps_id')}") do
            clone_info = dataset_info(services, response.fetch('cloned_vps_id'))
            !clone_info.nil?
          end

          wait_for_vps_on_node(
            services,
            vps_id: response.fetch('cloned_vps_id'),
            node_id: node2_id,
            running: true
          )
          clone_dataset_rows = vps_dataset_rows(services, response.fetch('cloned_vps_id'))
          clone_mount_rows = vps_mount_rows(services, response.fetch('cloned_vps_id'))
          clone_child_row = clone_dataset_rows.detect do |row|
            row.fetch('full_name').end_with?('/clone-desc-child')
          end
          clone_root_path = find_dataset_path_on_node(node2, clone_info.fetch('dataset_full_name'))
          clone_child_path = find_dataset_path_on_node(node2, clone_child_row.fetch('full_name'))
          clone_mount_row = clone_mount_rows.detect { |row| row.fetch('dst') == '/mnt/clone-desc' }
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            clone_info: clone_info,
            clone_dataset_rows: clone_dataset_rows,
            clone_mount_rows: clone_mount_rows,
            clone_child_row: clone_child_row,
            clone_mount_row: clone_mount_row,
            source_mount: mount
          }

          expect(clone_child_row).not_to be_nil, diagnostic.inspect
          expect(clone_mount_row).not_to be_nil, diagnostic.inspect
          expect(clone_mount_row.fetch('dataset_in_pool_id')).to eq(clone_child_row.fetch('dataset_in_pool_id')), diagnostic.inspect
          expect(clone_mount_row.fetch('dataset_in_pool_id')).not_to eq(mount.fetch('dataset_in_pool_id')), diagnostic.inspect
          expect(read_dataset_text(
            node2,
            dataset_path: clone_root_path,
            relative_path: 'root/root.txt'
          )).to include('clone descendant root sentinel'), diagnostic.inspect
          expect(read_dataset_text(
            node2,
            dataset_path: clone_child_path,
            relative_path: 'payload/child.txt'
          )).to include('clone descendant child sentinel'), diagnostic.inspect
        end
      end
    '';
  }
)
