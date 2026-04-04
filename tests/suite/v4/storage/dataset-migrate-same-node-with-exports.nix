import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };
  in
  {
    name = "storage-dataset-migrate-same-node-with-exports";

    description = ''
      Migrate an exported dataset between primary pools on the same node and
      verify the export is recreated for the destination dataset.
    '';

    tags = [
      "ci"
      "vpsadmin"
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

      describe 'same-node dataset migration with exports', order: :defined do
        it 'stops, destroys, and recreates the export on the destination dataset' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'dataset-export-same-src',
            filesystem: primary_pool_fs,
            role: 'primary'
          )
          dst_pool_fs = 'tank/export-dst'
          dst_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'dataset-export-same-dst',
            filesystem: dst_pool_fs,
            role: 'primary'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))
          wait_for_pool_online(services, dst_pool.fetch('id'))

          info = create_top_level_dataset(
            services,
            admin_user_id: admin_user_id,
            pool_id: src_pool.fetch('id'),
            dataset_name: 'dataset-migrate-same-export'
          )
          src_dataset_path = "#{primary_pool_fs}/#{info.fetch('dataset_full_name')}"

          write_dataset_text(
            node,
            dataset_path: src_dataset_path,
            relative_path: 'payload/sentinel.txt',
            content: "dataset migration sentinel\n"
          )
          checksum = write_dataset_payload(
            node,
            dataset_path: src_dataset_path,
            relative_path: 'payload/blob.bin',
            mib: 4
          )

          export_network = ensure_private_export_network_with_ips(
            services,
            admin_user_id: admin_user_id,
            dataset_id: info.fetch('dataset_id'),
            count: 1
          )
          export = create_export(
            services,
            admin_user_id: admin_user_id,
            dataset_id: info.fetch('dataset_id'),
            enabled: true
          )
          add_export_host(
            services,
            admin_user_id: admin_user_id,
            export_id: export.fetch('id'),
            ip_address_id: export_network.fetch('ip_addresses').first.fetch('id')
          )

          response = dataset_migrate(
            services,
            dataset_id: info.fetch('dataset_id'),
            pool_id: dst_pool.fetch('id'),
            send_mail: false
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
          dst_info = dataset_in_pool_info(
            services,
            dataset_id: info.fetch('dataset_id'),
            pool_id: dst_pool.fetch('id')
          )
          dst_dataset_path = "#{dst_pool_fs}/#{info.fetch('dataset_full_name')}"
          export_after = export_row(services, export.fetch('id'))

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), failure_details.inspect
          expect(handles).to include(
            tx_types(services).fetch('export_disable'),
            tx_types(services).fetch('export_del_hosts'),
            tx_types(services).fetch('export_destroy'),
            tx_types(services).fetch('export_create'),
            tx_types(services).fetch('export_add_hosts'),
            tx_types(services).fetch('export_enable')
          )
          expect(dst_info).not_to be_nil
          expect(export_after).not_to be_nil
          expect(export_after.fetch('dataset_in_pool_id')).to eq(dst_info.fetch('dataset_in_pool_id'))
          expect(export_after.fetch('enabled')).to be(true)
          expect(read_dataset_text(
            node,
            dataset_path: dst_dataset_path,
            relative_path: 'payload/sentinel.txt'
          )).to include('dataset migration sentinel')
          expect(file_checksum(
            node,
            dataset_path: dst_dataset_path,
            relative_path: 'payload/blob.bin'
          )).to eq(checksum)
        end
      end
    '';
  }
)
