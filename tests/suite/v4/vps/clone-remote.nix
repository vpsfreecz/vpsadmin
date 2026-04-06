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
    name = "vps-clone-remote";

    description = ''
      Clone a VPS to another node and verify the transferred data matches while
      the source VPS stays intact.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote VPS clone', order: :defined do
        it 'clones the VPS to node2 with remote send steps' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-clone-remote-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-clone-remote'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-clone-remote-dst',
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
            hostname: 'vps-clone-remote'
          )

          src_info = nil
          wait_until_block_succeeds(name: "source dataset info for VPS #{vps.fetch('id')}") do
            src_info = dataset_info(services, vps.fetch('id'))
            !src_info.nil?
          end

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          src_dataset_path = find_dataset_path_on_node(node1, src_info.fetch('dataset_full_name'))
          write_dataset_text(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/spec-clone.txt',
            content: "remote clone sentinel\n"
          )
          checksum = write_dataset_payload(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/blob.bin',
            mib: 4
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
          handles = chain_transactions(services, response.fetch('chain_id')).map do |row|
            row.fetch('handle')
          end
          chain_diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles
          }

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_diagnostic.inspect

          clone_info = nil
          wait_until_block_succeeds(name: "clone dataset info for VPS #{response.fetch('cloned_vps_id')}") do
            clone_info = dataset_info(services, response.fetch('cloned_vps_id'))
            !clone_info.nil?
          end

          clone_vps = wait_for_vps_on_node(
            services,
            vps_id: response.fetch('cloned_vps_id'),
            node_id: node2_id,
            running: true
          )
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)
          clone_dataset_path = find_dataset_path_on_node(node2, clone_info.fetch('dataset_full_name'))
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles,
            clone_vps: clone_vps,
            clone_info: clone_info
          }

          expect(handles).to include(
            tx_types(services).fetch('authorize_send_key'),
            tx_types(services).fetch('vps_send_config'),
            tx_types(services).fetch('vps_send_rootfs'),
            tx_types(services).fetch('vps_send_state'),
            tx_types(services).fetch('vps_send_cleanup')
          ), diagnostic.inspect
          expect(read_dataset_text(
            node2,
            dataset_path: clone_dataset_path,
            relative_path: 'root/spec-clone.txt'
          )).to include('remote clone sentinel'), diagnostic.inspect
          expect(file_checksum(
            node2,
            dataset_path: clone_dataset_path,
            relative_path: 'root/blob.bin'
          )).to eq(checksum), diagnostic.inspect
        end
      end
    '';
  }
)
