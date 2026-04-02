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
    name = "vps-migrate-interrupted-rsync";

    description = ''
      Exercise the current rsync-based migration cleanup path by failing the
      second rsync invocation during dataset migration, verifying source data
      stays intact, and confirming a later retry succeeds cleanly.
    '';

    tags = [
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'rsync migration interruption cleanup', order: :defined do
        it 'fails on the final rsync pass and succeeds after retry' do
          setup = create_primary_dataset(
            services,
            primary_node: node1,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'rsync-migrate-interrupt',
            primary_pool_fs: primary_pool_fs
          )
          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: setup.fetch('dataset_id'),
            name: 'rsync-migrate-interrupt-child',
            pool_fs: primary_pool_fs
          )
          dst_pool_fs = 'tank/rsync-dst'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'rsync-migrate-dst',
            filesystem: dst_pool_fs,
            role: 'primary'
          )

          wait_for_pool_online(services, dst_pool.fetch('id'))
          generate_migration_keys(services)

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'private/payload/sentinel.txt',
            content: "rsync interruption sentinel\n"
          )
          wait_until_block_succeeds(name: "descendant dataset #{child.fetch('dataset_path')} exists") do
            node1.zfs_exists?(child.fetch('dataset_path'), type: 'filesystem', timeout: 30)
          end
          write_dataset_text(
            node1,
            dataset_path: child.fetch('dataset_path'),
            relative_path: 'private/payload/descendant.txt',
            content: "descendant data\n"
          )
          checksum = write_dataset_payload(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'private/payload/blob.bin',
            mib: 8
          )

          faulty_rsync = '/run/vpsadmin-test-faulty-rsync'
          counter_path = '/run/vpsadmin-test-faulty-rsync.count'
          install_counting_rsync(
            node2,
            path: faulty_rsync,
            counter_path: counter_path,
            fail_on_invocation: 2
          )

          begin
            set_rsync_command(node2, command: faulty_rsync)
            response = dataset_migrate(
              services,
              dataset_id: setup.fetch('dataset_id'),
              pool_id: dst_pool.fetch('id'),
              rsync: true,
              send_mail: false,
              block: false
            )

            final_state = wait_for_chain_states_local(
              services,
              response.fetch('chain_id'),
              %i[done failed fatal resolved],
              timeout: 600
            )
            failure_details = chain_failure_details(services, response.fetch('chain_id'))
            failed_handles = failed_chain_transactions(
              services,
              response.fetch('chain_id')
            ).map { |row| row.fetch('handle') }

            expect(final_state).not_to eq(services.class::CHAIN_STATES[:done])
            expect(failure_details).not_to eq([])
            expect(failed_handles).to include(tx_types(services).fetch('rsync_dataset'))
            expect(chain_port_reservations(services, response.fetch('chain_id'))).to eq([])
            expect(read_dataset_text(
              node1,
              dataset_path: setup.fetch('primary_dataset_path'),
              relative_path: 'private/payload/sentinel.txt'
            )).to include('rsync interruption sentinel')
            expect(file_checksum(
              node1,
              dataset_path: setup.fetch('primary_dataset_path'),
              relative_path: 'private/payload/blob.bin'
            )).to eq(checksum)
          ensure
            reset_rsync_command(node2)
            node2.succeeds("rm -f #{Shellwords.escape(counter_path)}", timeout: 30)
          end

          retry_response = dataset_migrate(
            services,
            dataset_id: setup.fetch('dataset_id'),
            pool_id: dst_pool.fetch('id'),
            rsync: true,
            send_mail: false,
            block: false
          )
          retry_state = wait_for_chain_states_local(
            services,
            retry_response.fetch('chain_id'),
            %i[done failed fatal resolved],
            timeout: 600
          )
          dst_dataset_path = find_dataset_path_on_node(node2, setup.fetch('dataset_full_name'))

          expect(retry_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            retry_response.fetch('chain_id')
          ).inspect
          expect(read_dataset_text(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'private/payload/sentinel.txt'
          )).to include('rsync interruption sentinel')
          expect(file_checksum(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'private/payload/blob.bin'
          )).to eq(checksum)

          wait_until_block_succeeds(name: 'source dataset removed after retry') do
            expect(node1.zfs_exists?(setup.fetch('primary_dataset_path'), type: 'filesystem', timeout: 30)).to be(false)
            true
          end
        end
      end
    '';
  }
)
