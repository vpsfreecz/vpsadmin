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
    name = "storage-snapshot-download-remove";

    description = ''
      Create a ready snapshot download, delete it through the API, and verify
      both the database row and on-disk files are cleaned up.
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

      describe 'snapshot download deletion', order: :defined do
        it 'removes the database row, snapshot link, and download files' do
          setup = create_primary_dataset(
            services,
            primary_node: node,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'snapshot-download-remove',
            primary_pool_fs: primary_pool_fs
          )

          write_dataset_text(
            node,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'payload/remove.txt',
            content: "remove sentinel\n"
          )

          snapshot = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'remove-s1'
          )
          created = create_snapshot_download(
            services,
            snapshot_id: snapshot.fetch('id'),
            format: 'stream',
            send_mail: false
          )
          row = wait_for_snapshot_download_ready(services, created.fetch('id'))
          file_path = download_file_path(
            pool_fs: primary_pool_fs,
            secret_key: row.fetch('secret_key'),
            file_name: row.fetch('file_name')
          )
          secret_dir = download_secret_dir_path(
            pool_fs: primary_pool_fs,
            secret_key: row.fetch('secret_key')
          )

          deleted = delete_snapshot_download(
            services,
            download_id: created.fetch('id')
          )
          final_state = wait_for_chain_states_local(
            services,
            deleted.fetch('chain_id'),
            %i[done failed fatal resolved]
          )

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            deleted.fetch('chain_id')
          ).inspect

          wait_for_snapshot_download_deleted(services, created.fetch('id'))

          expect(snapshot_download_row(services, created.fetch('id'))).to be_nil
          expect(
            services.mysql_scalar(
              sql: "SELECT snapshot_download_id FROM snapshots WHERE id = #{snapshot.fetch('id')}"
            ).to_s
          ).to eq("NULL")

          node.succeeds("test ! -e #{Shellwords.escape(file_path)}")
          node.succeeds("test ! -e #{Shellwords.escape(secret_dir)}")
        end
      end
    '';
  }
)
