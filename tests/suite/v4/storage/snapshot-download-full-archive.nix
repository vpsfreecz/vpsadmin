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
    name = "storage-snapshot-download-full-archive";

    description = ''
      Create an archive-format snapshot download on a single node and verify
      the produced tarball contents plus the persisted download metadata.
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

      describe 'archive snapshot download', order: :defined do
        it 'writes a ready tarball and exposes it through the download row' do
          setup = create_primary_dataset(
            services,
            primary_node: node,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'snapshot-download-archive',
            primary_pool_fs: primary_pool_fs
          )

          write_dataset_text(
            node,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'payload/sentinel.txt',
            content: "archive sentinel\n"
          )
          write_dataset_payload(
            node,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'payload/random.bin',
            mib: 2
          )

          snapshot = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'archive-s1'
          )
          response = create_snapshot_download(
            services,
            snapshot_id: snapshot.fetch('id'),
            format: 'archive',
            send_mail: false
          )

          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          row = wait_for_snapshot_download_ready(services, response.fetch('id'))
          transactions = chain_transactions(services, response.fetch('chain_id'))
          file_path = download_file_path(
            pool_fs: primary_pool_fs,
            secret_key: row.fetch('secret_key'),
            file_name: row.fetch('file_name')
          )
          listing = gzip_stream_listing(node, file_path)

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            response.fetch('chain_id')
          ).inspect
          expect(row.fetch('confirmed')).to eq('confirmed')
          expect(row.fetch('format')).to eq('archive')
          expect(row.fetch('pool_id')).to eq(setup.fetch('primary_pool_id'))
          expect(row.fetch('file_name')).to end_with('.tar.gz')
          expect(row.fetch('sha256sum')).to match(/\A[0-9a-f]{64}\z/)
          expect(row.fetch('size')).not_to be_nil
          expect(row.fetch('url')).to include(
            row.fetch('secret_key'),
            row.fetch('file_name')
          )
          expect(transactions.map { |row| row.fetch('handle') }).to eq(
            [tx_types(services).fetch('download_snapshot')]
          )
          expect(transactions.first.fetch('queue')).to eq('general')
          expect(listing.join("\n")).to include(
            'payload/sentinel.txt',
            'payload/random.bin'
          )

          node.succeeds("test -f #{Shellwords.escape(file_path)}")
        end
      end
    '';
  }
)
