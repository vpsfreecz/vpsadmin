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
    name = "storage-snapshot-download-full-stream";

    description = ''
      Create a full ZFS stream snapshot download and verify the stored stream
      references the expected dataset and snapshot.
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
        ensure_snapshot_download_base_url(services)
      end

      describe 'full stream snapshot download', order: :defined do
        it 'writes a gzip-compressed ZFS send stream' do
          setup = create_primary_dataset(
            services,
            primary_node: node,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'snapshot-download-stream',
            primary_pool_fs: primary_pool_fs
          )

          write_dataset_text(
            node,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'root/stream.txt',
            content: "stream sentinel\n"
          )

          snapshot = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'stream-s1'
          )
          response = create_snapshot_download(
            services,
            snapshot_id: snapshot.fetch('id'),
            format: 'stream',
            send_mail: false
          )

          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          row = wait_for_snapshot_download_ready(services, response.fetch('id'))
          file_path = download_file_path(
            pool_fs: primary_pool_fs,
            secret_key: row.fetch('secret_key'),
            file_name: row.fetch('file_name')
          )
          stream_info = zstreamdump_output(node, file_path)

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            response.fetch('chain_id')
          ).inspect
          expect(row.fetch('confirmed')).to eq('confirmed')
          expect(row.fetch('format')).to eq('stream')
          expect(row.fetch('file_name')).to end_with('.dat.gz')
          expect(stream_info).to include(
            setup.fetch('dataset_full_name'),
            snapshot.fetch('name')
          )

          node.succeeds("test -f #{Shellwords.escape(file_path)}")
        end
      end
    '';
  }
)
