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
    name = "storage-dataset-migrate-same-node";

    description = ''
      Migrate a standalone dataset between primary pools on the same node and
      verify that its data moves to the destination pool.
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

      describe 'same-node dataset migration', order: :defined do
        it 'moves the dataset between primary pools on one node' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'dataset-same-node-src',
            filesystem: primary_pool_fs,
            role: 'primary'
          )
          dst_pool_fs = 'tank/ct-dst'
          dst_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'dataset-same-node-dst',
            filesystem: dst_pool_fs,
            role: 'primary'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))
          wait_for_pool_online(services, dst_pool.fetch('id'))

          info = create_top_level_dataset(
            services,
            admin_user_id: admin_user_id,
            pool_id: src_pool.fetch('id'),
            dataset_name: 'dataset-migrate-same-node'
          )
          src_dataset_path = "#{primary_pool_fs}/#{info.fetch('dataset_full_name')}"

          wait_until_block_succeeds(name: "source dataset #{src_dataset_path} exists") do
            node.zfs_exists?(src_dataset_path, type: 'filesystem', timeout: 30)
          end

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
          dst_info = dataset_in_pool_info(
            services,
            dataset_id: info.fetch('dataset_id'),
            pool_id: dst_pool.fetch('id')
          )
          dst_dataset_path = "#{dst_pool_fs}/#{info.fetch('dataset_full_name')}"

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), failure_details.inspect
          expect(dst_info).not_to be_nil
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

          wait_until_block_succeeds(name: 'source dataset removed after same-node migration') do
            expect(node.zfs_exists?(src_dataset_path, type: 'filesystem', timeout: 30)).to be(false)
            true
          end
        end
      end
    '';
  }
)
