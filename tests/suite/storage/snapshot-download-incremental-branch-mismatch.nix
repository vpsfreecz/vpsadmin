import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-2-node.nix;
    node1Seed = clusterSeed.nodes.node1;
    node2Seed = clusterSeed.nodes.node2;
    common = import ./remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = node1Seed.id;
      node2Id = node2Seed.id;
    };
  in
  {
    name = "storage-snapshot-download-incremental-branch-mismatch";

    description = ''
      Request an incremental download whose base and target snapshots are on
      the same backup pool but in different backup trees, and verify planning
      rejects the mismatched branch history before nodectld runs zfs send.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../machines/cluster/2-node.nix args;

    testScript = common + ''
      describe 'incremental download across mismatched backup branches', order: :defined do
        it 'fails during planning instead of sending from the wrong branch' do
          setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-download-branch-mismatch',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

          base = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'download-mismatch-s1'
          )
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'download-mismatch-s2'
          )

          reinstall = reinstall_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: setup.fetch('vps_id')
          )
          services.wait_for_chain_state(reinstall.fetch('chain_id'), state: :done)

          wait_until_block_succeeds(name: 'source snapshots removed before branch mismatch download') do
            snapshot_rows_for_dip(services, setup.fetch('src_dip_id')).empty?
          end

          target = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'download-mismatch-s3'
          )
          backup = fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id')
          )

          expect(head_tree_row(services, setup.fetch('dst_dip_id')).fetch('tree_index')).to eq(1)
          expect(chain_transactions(services, backup.fetch('chain_id')).map { |row| row.fetch('handle') }).to include(
            tx_types(services).fetch('create_tree')
          )

          result = services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}

            begin
              target = Snapshot.find(#{Integer(target.fetch('id'))})
              base = Snapshot.find(#{Integer(base.fetch('id'))})
              TransactionChains::Dataset::IncrementalDownload.fire(
                target,
                format: :incremental_stream,
                from_snapshot: base,
                send_mail: false
              )
              ok = true
              error_class = nil
              error_reason = nil
            rescue VpsAdmin::API::Exceptions::SnapshotDownloadUnavailable => e
              ok = false
              error_class = e.class.name
              error_reason = e.reason.to_s
            rescue => e
              ok = false
              error_class = e.class.name
              error_reason = nil
            end

            puts JSON.dump(
              ok: ok,
              error_class: error_class,
              error_reason: error_reason,
              downloads: SnapshotDownload.where(snapshot_id: #{Integer(target.fetch('id'))}).count
            )
          RUBY

          expect(result.fetch('ok')).to eq(false)
          expect(result.fetch('error_class')).to eq(
            'VpsAdmin::API::Exceptions::SnapshotDownloadUnavailable'
          )
          expect(result.fetch('error_reason')).to eq('no_common_source')
          expect(result.fetch('downloads')).to eq(0)
        end
      end
    '';
  }
)
