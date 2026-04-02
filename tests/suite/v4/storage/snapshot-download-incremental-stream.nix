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
    name = "storage-snapshot-download-incremental-stream";

    description = ''
      Produce an incremental snapshot download from a shared local history and
      verify both snapshot endpoints are referenced in the stream dump.
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

      describe 'incremental stream snapshot download', order: :defined do
        it 'creates a stream from a local shared history' do
          setup = create_primary_dataset(
            services,
            primary_node: node,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            dataset_name: 'snapshot-download-incremental',
            primary_pool_fs: primary_pool_fs
          )

          write_dataset_text(
            node,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'root/base.txt',
            content: "base version\n"
          )
          from_snapshot = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'inc-s1'
          )

          write_dataset_text(
            node,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'root/base.txt',
            content: "next version\n"
          )
          target_snapshot = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'inc-s2'
          )

          response = create_snapshot_download(
            services,
            snapshot_id: target_snapshot.fetch('id'),
            format: 'incremental_stream',
            from_snapshot_id: from_snapshot.fetch('id'),
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
          from_guid = zfs_guid(
            node,
            "#{setup.fetch('primary_dataset_path')}@#{from_snapshot.fetch('name')}"
          )
          target_guid = zfs_guid(
            node,
            "#{setup.fetch('primary_dataset_path')}@#{target_snapshot.fetch('name')}"
          )
          stream_info = zstreamdump_output(node, file_path)

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            response.fetch('chain_id')
          ).inspect
          expect(row.fetch('format')).to eq('incremental_stream')
          expect(row.fetch('file_name')).to include(
            from_snapshot.fetch('name').tr(':', '-'),
            target_snapshot.fetch('name').tr(':', '-')
          )
          expect(stream_info).to include(
            "fromguid = #{from_guid}",
            "toguid = #{target_guid}"
          )

          node.succeeds("test -f #{Shellwords.escape(file_path)}")
        end
      end
    '';
  }
)
