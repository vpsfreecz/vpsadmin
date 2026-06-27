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
    name = "storage-rollback-dependent-branch-rotation";

    description = ''
      Back up VPS snapshots, roll back across backup branches, append snapshots
      to the dependent backup branch, and verify rotation destroys the clone
      origin only after dependent snapshots are gone.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../machines/cluster/2-node.nix args;

    testScript = common + ''
      def rotate_dataset(services, admin_user_id:, dip_id:)
        response = services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          dip = DatasetInPool.find(#{dip_id})
          begin
            chain, = TransactionChains::Dataset::Rotate.fire(dip)
            puts JSON.dump(chain_id: chain.id, empty: false)
          rescue RuntimeError => e
            raise unless e.message == 'empty'

            puts JSON.dump(chain_id: nil, empty: true)
          end
        RUBY

        return response if response.fetch('empty', false)

        wait_for_chain_states_local(
          services,
          response.fetch('chain_id'),
          %i[done failed fatal resolved]
        )
        response
      end

      describe 'rotation after rollback back to a dependent backup branch', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-dependent-branch-rotation',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'backs up snapshots on a branch that remains a ZFS clone after rollback' do
          marker_path = 'rollback-rotation-marker.txt'

          write_dataset_text(
            node1,
            dataset_path: @setup.fetch('primary_dataset_path'),
            relative_path: marker_path,
            content: "s1\n"
          )
          @snap1 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'dependent-branch-rotation-s1'
          )

          write_dataset_text(
            node1,
            dataset_path: @setup.fetch('primary_dataset_path'),
            relative_path: marker_path,
            content: "s2\n"
          )
          @snap2 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'dependent-branch-rotation-s2'
          )

          write_dataset_text(
            node1,
            dataset_path: @setup.fetch('primary_dataset_path'),
            relative_path: marker_path,
            content: "s3\n"
          )
          @snap3 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'dependent-branch-rotation-s3'
          )

          rollback_s2 = rollback_dataset_to_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            snapshot_id: @snap2.fetch('id')
          )
          rollback_s2_state = wait_for_chain_states_local(
            services,
            rollback_s2.fetch('chain_id'),
            %i[done failed fatal resolved],
            timeout: 1200
          )
          expect(rollback_s2_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            rollback_s2.fetch('chain_id')
          ).inspect
          wait_for_vps_running(services, @setup.fetch('vps_id'))
          expect(
            read_dataset_text(
              node1,
              dataset_path: @setup.fetch('primary_dataset_path'),
              relative_path: marker_path
            )
          ).to eq("s2\n")

          rollback_s3 = rollback_dataset_to_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            snapshot_id: @snap3.fetch('id')
          )
          rollback_s3_state = wait_for_chain_states_local(
            services,
            rollback_s3.fetch('chain_id'),
            %i[done failed fatal resolved],
            timeout: 1200
          )
          expect(rollback_s3_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            rollback_s3.fetch('chain_id')
          ).inspect
          wait_for_vps_running(services, @setup.fetch('vps_id'))
          expect(
            read_dataset_text(
              node1,
              dataset_path: @setup.fetch('primary_dataset_path'),
              relative_path: marker_path
            )
          ).to eq("s3\n")

          write_dataset_text(
            node1,
            dataset_path: @setup.fetch('primary_dataset_path'),
            relative_path: marker_path,
            content: "s4\n"
          )
          @snap4 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'dependent-branch-rotation-s4'
          )

          write_dataset_text(
            node1,
            dataset_path: @setup.fetch('primary_dataset_path'),
            relative_path: marker_path,
            content: "s5\n"
          )
          @snap5 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'dependent-branch-rotation-s5'
          )

          @head_branch = head_branch_row(
            services,
            @setup.fetch('dst_dip_id')
          )
          @head_branch_path = branch_dataset_path(
            backup_pool_fs,
            @setup.fetch('dataset_full_name'),
            @head_branch
          )
          origin = zfs_branch_origin_map(
            node2,
            @setup.fetch('backup_dataset_path')
          ).fetch(@head_branch_path)

          expect(origin.split('@', 2).last).to eq(@snap2.fetch('name'))
        end

        it 'records appended backup snapshots as dependents of the clone origin' do
          entries = branch_entries_for_dip(
            services,
            @setup.fetch('dst_dip_id')
          )
          origin_entry = entries.find do |entry|
            entry.fetch('snapshot_name') == @snap2.fetch('name')
          end
          dependent_entries = [
            @snap3,
            @snap4,
            @snap5
          ].map do |snapshot|
            entries.find do |entry|
              entry.fetch('branch_id') == @head_branch.fetch('branch_id') &&
                entry.fetch('snapshot_name') == snapshot.fetch('name')
            end
          end

          expect(origin_entry).to be_a(Hash)
          expect(dependent_entries).to all(be_a(Hash))
          expect(dependent_entries.map { |entry| entry.fetch('parent_entry_id') }).to all(
            eq(origin_entry.fetch('entry_id'))
          )
          expect(origin_entry.fetch('reference_count')).to eq(dependent_entries.count)
        end

        it 'rotates the clone origin only after the dependent branch is gone' do
          long_age = 365 * 24 * 60 * 60

          set_snapshot_retention(
            services,
            dip_id: @setup.fetch('dst_dip_id'),
            min_snapshots: 0,
            max_snapshots: 3,
            snapshot_max_age: long_age
          )

          trim = rotate_dataset(
            services,
            admin_user_id: admin_user_id,
            dip_id: @setup.fetch('dst_dip_id')
          )
          expect(trim.fetch('empty', false)).to be(false)
          trim_state = services.mariadb_scalar(
            sql: "SELECT state FROM transaction_chains WHERE id = #{trim.fetch('chain_id')}"
          ).to_i
          expect(trim_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            trim.fetch('chain_id')
          ).inspect

          remaining_after_trim = wait_for_snapshot_names(
            services,
            dip_id: @setup.fetch('dst_dip_id'),
            include_names: [
              @snap2.fetch('name'),
              @snap4.fetch('name'),
              @snap5.fetch('name')
            ],
            exclude_names: [
              @snap1.fetch('name'),
              @snap3.fetch('name')
            ]
          )
          expect(remaining_after_trim).to match_array([
            @snap2.fetch('name'),
            @snap4.fetch('name'),
            @snap5.fetch('name')
          ])

          set_snapshot_retention(
            services,
            dip_id: @setup.fetch('dst_dip_id'),
            min_snapshots: 0,
            max_snapshots: 0,
            snapshot_max_age: long_age
          )

          rotation_chain_ids = []
          4.times do
            rotation = rotate_dataset(
              services,
              admin_user_id: admin_user_id,
              dip_id: @setup.fetch('dst_dip_id')
            )
            break if rotation.fetch('empty', false)

            rotation_chain_ids << rotation.fetch('chain_id')
            final_state = services.mariadb_scalar(
              sql: "SELECT state FROM transaction_chains WHERE id = #{rotation.fetch('chain_id')}"
            ).to_i

            expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
              services,
              rotation.fetch('chain_id')
            ).inspect
          end

          expect(rotation_chain_ids).not_to eq([])
          expect(snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id'))).to eq([])
          expect(branch_entries_for_dip(services, @setup.fetch('dst_dip_id'))).to eq([])
          expect(
            node2.zfs_exists?(@head_branch_path, type: 'filesystem', timeout: 30)
          ).to be(false)
        end
      end
    '';
  }
)
