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
    name = "vps-replace-same-node";

    description = ''
      Replace a VPS into another hypervisor pool on the same node and verify
      the replacement is running while the original stays soft-deleted.
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
        set_user_mailer_enabled(
          services,
          admin_user_id: admin_user_id,
          user_id: admin_user_id,
          enabled: false
        )
      end

      describe 'same-node VPS replace', order: :defined do
        it 'creates a replacement in another pool without remote send steps' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-replace-same-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-replace-same'
          )

          src_info = nil
          wait_until_block_succeeds(name: "source dataset info for VPS #{vps.fetch('id')}") do
            src_info = dataset_info(services, vps.fetch('id'))
            !src_info.nil?
          end

          dst_pool_fs = 'tank/ct-replace-same'
          dst_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-replace-same-dst',
            filesystem: dst_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, dst_pool.fetch('id'))

          services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}

            vps = Vps.find(#{Integer(vps.fetch('id'))})
            vps.update!(onstartall: true)
            puts JSON.dump(onstartall: vps.onstartall)
          RUBY

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)
          attach_test_vps_ip(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            addr: '198.51.100.10'
          )

          src_dataset_path = find_dataset_path_on_node(node, src_info.fetch('dataset_full_name'))
          write_dataset_text(
            node,
            dataset_path: src_dataset_path,
            relative_path: 'root/spec-replace.txt',
            content: "same-node replace sentinel\n"
          )
          checksum = write_dataset_payload(
            node,
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
            node_id: node1_id,
            start: true,
            reason: 'same-node replace integration'
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
            node_id: node1_id,
            running: true
          )
          old_row = vps_unscoped_row(services, vps.fetch('id'))
          new_row = vps_unscoped_row(services, response.fetch('replaced_vps_id'))
          new_netifs = vps_network_interface_rows(services, response.fetch('replaced_vps_id'))
          new_ips = vps_ip_rows(services, response.fetch('replaced_vps_id'))
          old_dataset_rows = vps_dataset_rows(services, vps.fetch('id'))
          new_dataset_rows = vps_dataset_rows(services, response.fetch('replaced_vps_id'))
          replacement_path = find_dataset_path_on_node(node, replacement_info.fetch('dataset_full_name'))
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles,
            old_row: old_row,
            new_row: new_row,
            new_netifs: new_netifs,
            new_ips: new_ips,
            old_dataset_rows: old_dataset_rows,
            new_dataset_rows: new_dataset_rows
          }

          expect(handles).to include(tx_types(services).fetch('vps_copy')), diagnostic.inspect
          expect(handles).not_to include(
            tx_types(services).fetch('authorize_send_key'),
            tx_types(services).fetch('vps_send_rootfs'),
            tx_types(services).fetch('vps_send_state')
          ), diagnostic.inspect
          expect(old_row.fetch('object_state')).to eq('soft_delete'), diagnostic.inspect
          expect([0, false]).to include(old_row.fetch('autostart_enable')), diagnostic.inspect
          expect(new_netifs).not_to eq([]), diagnostic.inspect
          expect(new_netifs.map { |row| row.fetch('vps_id') }.uniq).to eq([response.fetch('replaced_vps_id')]), diagnostic.inspect
          expect(new_ips).not_to eq([]), diagnostic.inspect
          expect(old_dataset_rows.map { |row| row.fetch('pool_filesystem') }.uniq).to eq([primary_pool_fs]), diagnostic.inspect
          expect(new_dataset_rows.map { |row| row.fetch('pool_filesystem') }.uniq).to eq([dst_pool_fs]), diagnostic.inspect
          expect(read_dataset_text(
            node,
            dataset_path: replacement_path,
            relative_path: 'root/spec-replace.txt'
          )).to include('same-node replace sentinel'), diagnostic.inspect
          expect(file_checksum(
            node,
            dataset_path: replacement_path,
            relative_path: 'root/blob.bin'
          )).to eq(checksum), diagnostic.inspect
        end
      end
    '';
  }
)
