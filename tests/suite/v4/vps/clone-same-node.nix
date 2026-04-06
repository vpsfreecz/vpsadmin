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
    name = "vps-clone-same-node";

    description = ''
      Clone a VPS between two hypervisor pools on the same node and verify the
      destination data matches without using remote send steps.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        prepare_node_queues(node)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'same-node VPS clone', order: :defined do
        it 'copies the VPS into another pool on the same node' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-clone-same-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-clone-same-node'
          )

          src_info = nil
          wait_until_block_succeeds(name: "source dataset info for VPS #{vps.fetch('id')}") do
            src_info = dataset_info(services, vps.fetch('id'))
            !src_info.nil?
          end

          dst_pool_fs = 'tank/ct-clone-same'
          dst_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-clone-same-dst',
            filesystem: dst_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, dst_pool.fetch('id'))

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          src_dataset_path = find_dataset_path_on_node(node, src_info.fetch('dataset_full_name'))
          write_dataset_text(
            node,
            dataset_path: src_dataset_path,
            relative_path: 'root/spec-clone.txt',
            content: "same-node clone sentinel\n"
          )
          checksum = write_dataset_payload(
            node,
            dataset_path: src_dataset_path,
            relative_path: 'root/blob.bin',
            mib: 4
          )

          response = vps_clone(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            node_id: node1_id,
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
            node_id: node1_id,
            running: true
          )
          clone_row = vps_unscoped_row(services, response.fetch('cloned_vps_id'))
          clone_dataset_path = find_dataset_path_on_node(node, clone_info.fetch('dataset_full_name'))
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles,
            clone_vps: clone_vps,
            clone_row: clone_row,
            clone_info: clone_info
          }

          expect(handles).to include(tx_types(services).fetch('vps_copy')), diagnostic.inspect
          expect(handles).not_to include(
            tx_types(services).fetch('authorize_send_key'),
            tx_types(services).fetch('vps_send_rootfs'),
            tx_types(services).fetch('vps_send_state')
          ), diagnostic.inspect
          expect(vps_unscoped_row(services, vps.fetch('id'))).not_to be_nil
          expect(clone_row).not_to be_nil
          expect(clone_info.fetch('pool_filesystem')).to eq(dst_pool_fs), diagnostic.inspect
          expect(read_dataset_text(
            node,
            dataset_path: clone_dataset_path,
            relative_path: 'root/spec-clone.txt'
          )).to include('same-node clone sentinel'), diagnostic.inspect
          expect(file_checksum(
            node,
            dataset_path: clone_dataset_path,
            relative_path: 'root/blob.bin'
          )).to eq(checksum), diagnostic.inspect
        end
      end
    '';
  }
)
