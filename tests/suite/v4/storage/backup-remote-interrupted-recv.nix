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
    name = "storage-backup-remote-interrupted-recv";

    description = ''
      Interrupt remote backup on the receiver side, verify cleanup of partial
      state and port reservations, and confirm a later backup succeeds.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote backup interrupted on recv', order: :defined do
        it 'fails cleanly when the receiver side is interrupted and later backup still works' do
          setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-interrupt-recv',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

          base = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'interrupt-recv-s1'
          )
          write_dataset_payload(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'var/tmp/recv.bin',
            mib: 64
          )
          snap2 = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'interrupt-recv-s2'
          )

          faulty_mbuffer = '/run/vpsadmin-test-faulty-mbuffer'
          install_faulty_mbuffer(
            node2,
            path: faulty_mbuffer,
            fail_after_bytes: 1 * 1024 * 1024
          )
          set_mbuffer_command(
            node2,
            direction: :receive,
            command: faulty_mbuffer
          )

          response = fire_backup_async(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id')
          )

          wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[failed fatal resolved]
          )

          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          chain_txs = chain_transactions(services, response.fetch('chain_id'))
          failed_handles = failed_chain_transactions(
            services,
            response.fetch('chain_id')
          ).map { |tx| tx.fetch('handle') }
          recv_check_detail = wait_for_chain_failure_detail(
            services,
            response.fetch('chain_id'),
            handle: @tx_types.fetch('recv_check')
          )
          recv_tx = chain_txs.detect do |tx|
            tx.fetch('handle') == @tx_types.fetch('recv')
          end
          backup_names = wait_for_snapshot_names(
            services,
            dip_id: setup.fetch('dst_dip_id'),
            include_names: [base.fetch('name')],
            exclude_names: [snap2.fetch('name')]
          )

          reset_mbuffer_command(node2, direction: :receive)

          expect(failure_details).not_to eq([])
          expect(recv_check_detail).not_to be_nil
          expect(recv_tx).not_to be_nil
          expect(
            grep_nodectld_log(
              node2,
              "chain=#{response.fetch('chain_id')},trans=#{recv_tx.fetch('id')},type=execute] " \
              "fork /run/vpsadmin-test-faulty-mbuffer"
            )
          ).to include(
            '/run/vpsadmin-test-faulty-mbuffer'
          )
          expect(failed_handles).to include(@tx_types.fetch('recv_check'))
          expect(backup_names).to include(base.fetch('name'))
          expect(backup_names).not_to include(snap2.fetch('name'))
          expect(chain_port_reservations(services, response.fetch('chain_id'))).to eq([])

          retry_response = fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id')
          )

          expect(retry_response.fetch('chain_id')).not_to be_nil
          expect(
            wait_for_snapshot_names(
              services,
              dip_id: setup.fetch('dst_dip_id'),
              include_names: [snap2.fetch('name')]
            )
          ).to include(snap2.fetch('name'))
        end
      end
    '';
  }
)
