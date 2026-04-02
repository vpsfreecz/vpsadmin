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
    name = "storage-dataset-migrate-remote";

    description = ''
      Migrate a standalone primary dataset to another node, verify its data on
      the destination pool, and ensure source-side data is cleaned up.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote dataset migration', order: :defined do
        it 'moves the dataset to another primary pool with its data intact' do
          setup = create_primary_dataset(
            services,
            primary_node: node1,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'dataset-migrate-remote',
            primary_pool_fs: primary_pool_fs
          )
          dst_pool_fs = 'tank/ct-dst'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'dataset-migrate-dst',
            filesystem: dst_pool_fs,
            role: 'primary'
          )

          wait_for_pool_online(services, dst_pool.fetch('id'))
          generate_migration_keys(services)

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'payload/sentinel.txt',
            content: "dataset migration sentinel\n"
          )
          checksum = write_dataset_payload(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'payload/blob.bin',
            mib: 4
          )

          response = dataset_migrate(
            services,
            dataset_id: setup.fetch('dataset_id'),
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
            dataset_id: setup.fetch('dataset_id'),
            pool_id: dst_pool.fetch('id')
          )
          dst_dataset_path = "#{dst_pool_fs}/#{setup.fetch('dataset_full_name')}"

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), failure_details.inspect
          expect(dst_info).not_to be_nil
          expect(read_dataset_text(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'payload/sentinel.txt'
          )).to include('dataset migration sentinel')
          expect(file_checksum(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'payload/blob.bin'
          )).to eq(checksum)

          wait_until_block_succeeds(name: 'source dataset removed after migration') do
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
