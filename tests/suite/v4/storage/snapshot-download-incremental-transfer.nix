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
    name = "storage-snapshot-download-incremental-transfer";

    description = ''
      Request an incremental download where the base snapshot already exists on
      backup, transfer the target snapshot there, and download the final stream
      from the backup pool.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      before(:suite) do
        ensure_snapshot_download_base_url(services)
      end

      describe 'incremental download with transfer to backup', order: :defined do
        it 'transfers the missing target snapshot before producing the stream' do
          setup = create_remote_backup_dataset(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            dataset_name: 'snapshot-download-transfer',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'payload/base.txt',
            content: "base version\n"
          )
          base = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'transfer-s1'
          )

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'payload/base.txt',
            content: "target version\n"
          )
          target = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'transfer-s2'
          )

          response = create_snapshot_download(
            services,
            snapshot_id: target.fetch('id'),
            format: 'incremental_stream',
            from_snapshot_id: base.fetch('id'),
            send_mail: false
          )

          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          row = wait_for_snapshot_download_ready(services, response.fetch('id'))
          handles = chain_transactions(services, response.fetch('chain_id')).map do |row|
            row.fetch('handle')
          end
          backup_names = wait_for_snapshot_names(
            services,
            dip_id: setup.fetch('dst_dip_id'),
            include_names: [target.fetch('name')]
          )
          file_path = download_file_path(
            pool_fs: backup_pool_fs,
            secret_key: row.fetch('secret_key'),
            file_name: row.fetch('file_name')
          )
          base_guid = zfs_guid(
            node1,
            "#{setup.fetch('primary_dataset_path')}@#{base.fetch('name')}"
          )
          target_guid = zfs_guid(
            node1,
            "#{setup.fetch('primary_dataset_path')}@#{target.fetch('name')}"
          )
          stream_info = zstreamdump_output(node2, file_path)

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            response.fetch('chain_id')
          ).inspect
          expect(row.fetch('pool_id')).to eq(setup.fetch('backup_pool_id'))
          expect(handles).to include(
            tx_types(services).fetch('recv'),
            tx_types(services).fetch('send'),
            tx_types(services).fetch('recv_check'),
            tx_types(services).fetch('download_snapshot')
          )
          expect(backup_names).to include(target.fetch('name'))
          expect(stream_info).to include(
            "fromguid = #{base_guid}",
            "toguid = #{target_guid}"
          )

          node2.succeeds("test -f #{Shellwords.escape(file_path)}")
        end
      end
    '';
  }
)
