import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-2-node.nix;
    node1Seed = clusterSeed.nodes.node1;
    node2Seed = clusterSeed.nodes.node2;
    common = import ./remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = node1Seed.id;
      node2Id = node2Seed.id;
    };
  in
  {
    name = "storage-dataset-migrate-rsync-remote";

    description = ''
      Migrate a standalone primary dataset to another node using rsync,
      verify the data on the destination pool, and ensure the source dataset is
      removed afterwards.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote dataset migration over rsync', order: :defined do
        it 'moves the dataset with rsync-specific transactions and intact data' do
          setup = create_primary_dataset(
            services,
            primary_node: node1,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'dataset-migrate-rsync-remote',
            primary_pool_fs: primary_pool_fs
          )
          dst_pool_fs = 'tank/ct-rsync-dst'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'dataset-rsync-dst',
            filesystem: dst_pool_fs,
            role: 'primary'
          )

          wait_for_pool_online(services, dst_pool.fetch('id'))
          generate_migration_keys(services)

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'private/payload/sentinel.txt',
            content: "dataset migration sentinel\n"
          )
          checksum = write_dataset_payload(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'private/payload/blob.bin',
            mib: 4
          )

          response = dataset_migrate(
            services,
            dataset_id: setup.fetch('dataset_id'),
            pool_id: dst_pool.fetch('id'),
            rsync: true,
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
            dataset_id: setup.fetch('dataset_id'),
            pool_id: dst_pool.fetch('id')
          )
          dst_dataset_path = find_dataset_path_on_node(node2, setup.fetch('dataset_full_name'))

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), failure_details.inspect
          expect(handles).to include(
            tx_types(services).fetch('rsync_dataset'),
            tx_types(services).fetch('authorize_rsync_key'),
            tx_types(services).fetch('revoke_rsync_key')
          )
          expect(handles).not_to include(
            tx_types(services).fetch('recv'),
            tx_types(services).fetch('send')
          )
          expect(dst_info).not_to be_nil
          expect(read_dataset_text(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'private/payload/sentinel.txt'
          )).to include('dataset migration sentinel')
          expect(file_checksum(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'private/payload/blob.bin'
          )).to eq(checksum)

          wait_until_block_succeeds(name: 'source dataset removed after rsync migration') do
            expect(
              node1.zfs_exists?(setup.fetch('primary_dataset_path'), type: 'filesystem', timeout: 30)
            ).to be(false)
            true
          end
        end
      end
    '';
  }
)
