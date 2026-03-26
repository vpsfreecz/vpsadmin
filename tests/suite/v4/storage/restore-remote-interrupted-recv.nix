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
    name = "storage-restore-remote-interrupted-recv";

    description = ''
      Interrupt remote restore on the primary receive side, verify rollback
      cleanup removes temporary rollback datasets, and confirm retry succeeds.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote restore interrupted on recv', order: :defined do
        it 'cleans up rollback state when primary receive is interrupted and retry succeeds' do
          setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-restore-interrupt',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'etc/restore-marker',
            content: "root-s1\n"
          )
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'interrupt-restore-s1'
          )

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'etc/restore-marker',
            content: "root-s2\n"
          )
          snap2 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'interrupt-restore-s2'
          )

          reinstall = reinstall_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: setup.fetch('vps_id')
          )
          services.wait_for_chain_state(reinstall.fetch('chain_id'), state: :done)

          wait_until_block_succeeds(name: 'local snapshots removed after reinstall for interrupted restore') do
            snapshot_rows_for_dip(services, setup.fetch('src_dip_id')).empty?
          end

          faulty_mbuffer = '/run/vpsadmin-test-faulty-mbuffer'
          install_faulty_mbuffer(
            node1,
            path: faulty_mbuffer,
            fail_after_bytes: 1 * 1024 * 1024
          )
          set_mbuffer_command(
            node1,
            direction: :receive,
            command: faulty_mbuffer
          )

          response = rollback_dataset_to_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            snapshot_id: snap2.fetch('id')
          )

          wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[failed fatal resolved]
          )

          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          chain_txs = chain_transactions(services, response.fetch('chain_id'))
          recv_check_detail = wait_for_chain_failure_detail(
            services,
            response.fetch('chain_id'),
            handle: tx_types(services).fetch('recv_check')
          )
          recv_tx = chain_txs.detect do |tx|
            tx.fetch('handle') == tx_types(services).fetch('recv')
          end

          reset_mbuffer_command(node1, direction: :receive)

          expect(failure_details).not_to eq([])
          expect(recv_check_detail).not_to be_nil
          expect(recv_tx).not_to be_nil
          expect(
            grep_nodectld_log(
              node1,
              "chain=#{response.fetch('chain_id')},trans=#{recv_tx.fetch('id')},type=execute] " \
              "fork /run/vpsadmin-test-faulty-mbuffer"
            )
          ).to include(
            '/run/vpsadmin-test-faulty-mbuffer'
          )
          expect(rollback_dataset_exists?(node1, setup.fetch('primary_dataset_path'))).to be(false)
          expect(chain_port_reservations(services, response.fetch('chain_id'))).to eq([])
          expect(
            node1.zfs_exists?(
              setup.fetch('primary_dataset_path'),
              type: 'filesystem',
              timeout: 30
            )
          ).to be(true)

          retry_restore = rollback_dataset_to_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            snapshot_id: snap2.fetch('id')
          )
          services.wait_for_chain_state(retry_restore.fetch('chain_id'), state: :done)
          wait_for_vps_running(services, setup.fetch('vps_id'))

          expect(rollback_dataset_exists?(node1, setup.fetch('primary_dataset_path'))).to be(false)
          expect(
            read_dataset_text(
              node1,
              dataset_path: setup.fetch('primary_dataset_path'),
              relative_path: 'etc/restore-marker'
            )
          ).to eq("root-s2\n")
        end
      end
    '';
  }
)
