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
      manageCluster = false;
    };
  in
  {
    name = "vps-replace-no-start";

    description = ''
      Replace a VPS onto another node with start=false, verify the replacement
      stays stopped, and confirm the copied data is present on the destination.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      before(:suite) do
        [services, node1, node2].each(&:start)
        services.wait_for_vpsadmin_api
        [node1, node2].each do |machine|
          wait_for_running_nodectld(machine)
          prepare_node_queues(machine)
        end
        [node1_id, node2_id].each do |node_id|
          wait_for_node_ready(services, node_id)
        end
        services.unlock_transaction_signing_key(passphrase: 'test')
        set_user_mailer_enabled(
          services,
          admin_user_id: admin_user_id,
          user_id: admin_user_id,
          enabled: false
        )
      end

      describe 'remote VPS replace with start=false', order: :defined do
        it 'finishes without starting the replacement on the destination' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-replace-no-start-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-replace-no-start'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-replace-no-start-dst',
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
            hostname: 'vps-replace-no-start'
          )

          src_info = nil
          wait_until_block_succeeds(name: "source dataset info for VPS #{vps.fetch('id')}") do
            src_info = dataset_info(services, vps.fetch('id'))
            !src_info.nil?
          end

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)
          attach_test_vps_ip(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            addr: '198.51.100.30'
          )

          src_dataset_path = find_dataset_path_on_node(node1, src_info.fetch('dataset_full_name'))
          write_dataset_text(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/spec-replace.txt',
            content: "replace no-start sentinel\n"
          )
          checksum = write_dataset_payload(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/blob.bin',
            mib: 4
          )
          services.vpsadminctl.succeeds(
            args: ['vps', 'stop', vps.fetch('id').to_s],
            parameters: { force: true }
          )
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: false)

          response = vps_replace(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            node_id: node2_id,
            start: false,
            reason: 'replace no-start integration'
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

          replacement_info = nil
          wait_until_block_succeeds(name: "replacement dataset info for VPS #{response.fetch('replaced_vps_id')}") do
            replacement_info = dataset_info(services, response.fetch('replaced_vps_id'))
            !replacement_info.nil?
          end

          wait_for_vps_on_node(
            services,
            vps_id: response.fetch('replaced_vps_id'),
            node_id: node2_id,
            running: false
          )
          replacement_path = find_dataset_path_on_node(node2, replacement_info.fetch('dataset_full_name'))
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles,
            replacement_info: replacement_info
          }

          expect(handles).not_to include(tx_types(services).fetch('vps_start')), diagnostic.inspect
          expect(vps_unscoped_row(services, vps.fetch('id')).fetch('object_state')).to eq('soft_delete'), diagnostic.inspect
          expect(read_dataset_text(
            node2,
            dataset_path: replacement_path,
            relative_path: 'root/spec-replace.txt'
          )).to include('replace no-start sentinel'), diagnostic.inspect
          expect(file_checksum(
            node2,
            dataset_path: replacement_path,
            relative_path: 'root/blob.bin'
          )).to eq(checksum), diagnostic.inspect
        end
      end
    '';
  }
)
