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
    name = "storage-backup-remote-interrupted-send";

    description = ''
      Interrupt backup-first preservation on the sender side, retain source
      data and plans, then deliberately retry the ordinary operation.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../machines/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote backup interrupted on send', order: :defined do
        it 'keeps source data and plans after failed preservation and allows a deliberate retry' do
          setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-interrupt-send',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
          services.succeeds('systemctl stop vpsadmin-scheduler.service')
          ensure_dataset_backup_plan(services, dataset_id: setup.fetch('dataset_id'))
          [setup.fetch('src_dip_id'), setup.fetch('dst_dip_id')].each do |copy|
            set_snapshot_retention(services, dip_id: copy, min_snapshots: 100,
                                   max_snapshots: 100, snapshot_max_age: 0)
          end
          plans_before = dataset_backup_plan_rows(services, setup.fetch('src_dip_id'))
          expect(plans_before).not_to be_empty
          base_checksum = write_dataset_payload(
            node1, dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'var/tmp/send.bin', mib: 8
          )

          base = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'interrupt-send-s1'
          )
          checksum = write_dataset_payload(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'var/tmp/send.bin',
            mib: 256
          )
          snap2 = create_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            dip_id: setup.fetch('src_dip_id'),
            label: 'interrupt-send-s2'
          )

          faulty_mbuffer = '/run/vpsadmin-test-faulty-mbuffer'
          install_faulty_mbuffer(
            node1,
            path: faulty_mbuffer,
            fail_after_bytes: 1 * 1024 * 1024
          )
          set_mbuffer_command(
            node1,
            direction: :send,
            command: faulty_mbuffer
          )

          source_before = snapshot_rows_for_dip(services, setup.fetch('src_dip_id'))
          response = disable_backups(services, dataset_id: setup.fetch('dataset_id'))

          wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[failed fatal resolved]
          )

          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          failed_handles = failed_chain_transactions(
            services,
            response.fetch('chain_id')
          ).map { |tx| tx.fetch('handle') }
          send_detail = wait_for_chain_failure_output_value(
            services,
            response.fetch('chain_id'),
            handle: tx_types(services).fetch('send'),
            path: %w[output exitstatus]
          )
          backup_names = wait_for_snapshot_names(
            services,
            dip_id: setup.fetch('dst_dip_id'),
            include_names: [base.fetch('name')],
            exclude_names: [snap2.fetch('name')]
          )

          reset_mbuffer_command(node1, direction: :send)

          expect(failure_details).not_to eq([])
          expect(send_detail).not_to be_nil
          expect(send_detail.dig('failure_output', 'exitstatus')).to eq(1)
          expect(send_detail.dig('failure_output', 'cmd')).to include(
            '/run/vpsadmin-test-faulty-mbuffer'
          )
          expect(failed_handles).to include(tx_types(services).fetch('recv_check'))
          expect(backup_names).to include(base.fetch('name'))
          expect(backup_names).not_to include(snap2.fetch('name'))
          expect(chain_port_reservations(services, response.fetch('chain_id'))).to eq([])
          expect(snapshot_rows_for_dip(services, setup.fetch('src_dip_id'))).to eq(source_before)
          expect(dataset_backup_plan_rows(services, setup.fetch('src_dip_id'))).to eq(plans_before)
          expect(file_checksum(node1, dataset_path: setup.fetch('primary_dataset_path'),
                               relative_path: 'var/tmp/send.bin')).to eq(checksum)
          destroys = failure_details.select { |tx| tx.fetch('handle') == tx_types(services).fetch('destroy_snapshot') }
          expect(destroys.size).to eq(source_before.size)
          expect(destroys.map { |tx| tx.fetch('error') }).to all(eq('Dependency failed'))
          # Both source snapshots still contain their original data. The failed
          # preservation has not reached source destruction or plan removal.
          [[base, base_checksum], [snap2, checksum]].each do |snapshot, expected_checksum|
            expect(file_checksum(node1, dataset_path: setup.fetch('primary_dataset_path'),
                                 relative_path: ".zfs/snapshot/#{snapshot.fetch('name')}/var/tmp/send.bin")).to eq(expected_checksum)
          end

          retry_response = disable_backups(services, dataset_id: setup.fetch('dataset_id'))
          services.wait_for_chain_state(retry_response.fetch('chain_id'), state: :done, timeout: 1200)

          expect(retry_response.fetch('chain_id')).not_to be_nil
          expect(
            wait_for_snapshot_names(
              services,
              dip_id: setup.fetch('dst_dip_id'),
              include_names: [snap2.fetch('name')]
            )
          ).to include(snap2.fetch('name'))
          expect(snapshot_rows_for_dip(services, setup.fetch('src_dip_id'))).to be_empty
          expect(dataset_backup_plan_rows(services, setup.fetch('src_dip_id'))).to be_empty
          expect(head_branch_row(services, setup.fetch('dst_dip_id'))).to be_nil
          head = branch_rows_for_dip(services, setup.fetch('dst_dip_id')).last
          backup_path = branch_dataset_path(backup_pool_fs, setup.fetch('dataset_full_name'), head)
          expect(file_checksum(node1, dataset_path: setup.fetch('primary_dataset_path'),
                               relative_path: 'var/tmp/send.bin')).to eq(checksum)
          [[base, base_checksum], [snap2, checksum]].each do |snapshot, expected_checksum|
            expect(file_checksum(node2, dataset_path: backup_path,
                                 relative_path: ".zfs/snapshot/#{snapshot.fetch('name')}/var/tmp/send.bin")).to eq(expected_checksum)
          end
        end
      end
    '';
  }
)
