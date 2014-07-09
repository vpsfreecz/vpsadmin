module Tasks
  class DatasetAction < Task
    ACTIONS = %i(snapshot transfer rollback)

    def self.query_params(task)
      "SELECT a.*,
        src_ds.name AS src_ds_name, src_ds.id AS src_ds_id,
        src_pool.node_id AS src_node_id, dst_pool.node_id AS dst_node_id,
        src_node.server_ip4 AS src_node_addr,
        src_pool.filesystem AS src_pool_fs, dst_pool.filesystem AS dst_pool_fs,
        src_pool.role AS src_pool_role, dst_pool.role AS dst_pool_role,
        vps.vps_id
      FROM #{task['table_name']} a
      LEFT JOIN pools p ON p.id = a.pool_id
      LEFT JOIN dataset_in_pools src_pool_ds ON src_pool_ds.id = a.src_dataset_in_pool_id
      LEFT JOIN datasets src_ds ON src_pool_ds.dataset_id = src_ds.id
      LEFT JOIN pools src_pool ON src_pool.id = src_pool_ds.pool_id
      LEFT JOIN servers src_node ON src_node.server_id = src_pool.node_id
      LEFT JOIN vps ON vps.dataset_in_pool_id = a.src_dataset_in_pool_id
      LEFT JOIN dataset_in_pools dst_pool_ds ON dst_pool_ds.id = a.dst_dataset_in_pool_id
      LEFT JOIN pools dst_pool ON dst_pool.id = dst_pool_ds.pool_id
      LEFT JOIN snapshots snap ON snap.id = a.snapshot_id
      LEFT JOIN dataset_actions dep ON dep.id = a.dependency_id
      WHERE a.id = #{task['object_id']}"
    end

    def execute
      method(ACTIONS[@action.to_i]).call
    end

    def snapshot
      log "execute dataset_action#snapshot #{@src_dataset_in_pool_id}"

      snap = Time.new.strftime('%Y-%m-%dT%H:%M:%S')

      @db.prepared(
          'INSERT INTO snapshots (name, dataset_id, confirmed) VALUES (?, ?, 0)',
          "#{snap} (unconfirmed)", @src_ds_id
      )

      snap_id = @db.insert_id

      @db.prepared(
          'INSERT INTO snapshot_in_pools (snapshot_id, dataset_in_pool_id, confirmed) VALUES (?, ?, 0)',
          snap_id, @src_dataset_in_pool_id
      )

      snap_in_pool_id = @db.insert_id

      t = Transaction.new(@db)
      t_id = t.prepare({
          node: @src_node_id,
          vps: @vps_id,
          type: :dataset_snapshot,
          param: {
              pool: @src_pool_fs,
              dataset_name: @src_ds_name,
              snapshot_id: snap_id,
              snapshot_in_pool_id: snap_in_pool_id
          }
      })

      t.confirm_create(t_id, 'Snapshot', 'snapshots', snap_id)
      t.confirm_create(t_id, 'SnapshotInPool', 'snapshot_in_pools', snap_in_pool_id)
      t.confirm(t_id)
    end

    def transfer
      log "execute dataset_action#transfer #{@src_dataset_in_pool_id}"

      t = Transaction.new(@db)
      branch_id = branch_name = nil

      # select the last snapshot from the destination
      st = @db.prepared_st(
          'SELECT s.id, s.name, s.confirmed
          FROM snapshot_in_pools sip
          INNER JOIN snapshots s ON s.id = sip.snapshot_id
          WHERE dataset_in_pool_id = ?
          ORDER BY snapshot_id DESC
          LIMIT 1',
          @dst_dataset_in_pool_id
      )

      # no snapshots on the destination
      if st.num_rows == 0
        st.close

        # send everything
        # - first send the first snapshot from src to dst
        # - then send all snapshots incrementally, if there are any

        # select all snapshots from source
        st = @db.prepared_st(
            'SELECT s.id, s.name, s.confirmed
            FROM snapshot_in_pools sip
            INNER JOIN snapshots s ON s.id = sip.snapshot_id
            WHERE dataset_in_pool_id = ?
            ORDER BY snapshot_id ASC',
            @src_dataset_in_pool_id
        )

        if st.num_rows == 0
          # no snapshots on source, nothing to send
          st.close
          return
        end

        all_snapshots = []

        st.each do |row|
          all_snapshots << {
              id: row[0],
              name: row[1],
              confirmed: row[2]
          }
        end

        t_id = nil

        # if branched
        #   create branch unless it exists
        #   mark branch as head
        #   put all snapshots inside it
        if dst_branched?
          st = @db.prepared_st('SELECT name FROM branches WHERE dataset_in_pool_id = ? LIMIT 1', @dst_dataset_in_pool_id)

          if st.num_rows > 0
            branch_name = st.fetch[0]

          else
            branch_name = Time.new.strftime('%Y-%m-%dT%H:%M:%S')

            @db.prepared(
                'INSERT INTO branches (dataset_in_pool_id, name, created_at, head, confirmed)
                VALUES (?, ?, NOW(), 1, 0)',
                @dst_dataset_in_pool_id, branch_name
            )

            branch_id = @db.insert_id

            t_id = t.prepare({
                                 node: @dst_node_id,
                                 vps: @vps_id,
                                 type: :dataset_create,
                                 param: {
                                     pool_fs: @dst_pool_fs,
                                     name: "#{@src_ds_name}/#{branch_name}"
                                 }
                             })

            t.confirm_create(t_id, 'Branch', 'branches', branch_id)
            t.confirm(t_id)
          end
        end

        t_id = t.prepare({
             node: @dst_node_id,
             vps: @vps_id,
             type: :dataset_transfer,
             depends: t_id,
             param: {
                 src_node_addr: @src_node_addr,
                 src_pool_fs: @src_pool_fs,
                 dst_pool_fs: @dst_pool_fs,
                 dataset_name: @src_ds_name,
                 snapshots: all_snapshots,
                 initial: true,
                 branch: branch_name
             }
         })

        all_snapshots.each do |snap|
          @db.prepared(
              'INSERT INTO snapshot_in_pools (snapshot_id, dataset_in_pool_id, confirmed)
              VALUES (?, ?, 0)',
              snap[:id], @dst_dataset_in_pool_id
          )

          sip_id = @db.insert_id

          t.confirm_create(t_id, 'SnapshotInPool', 'snapshot_in_pools', sip_id)

          if dst_branched?
            @db.prepared(
                'INSERT INTO snapshot_in_pool_in_branches (snapshot_in_pool_id, branch_id, confirmed)
                VALUES (?, ?, 0)',
                sip_id, branch_id
            )

            t.confirm_create(t_id, 'SnapshotInPoolInBranches', 'snapshot_in_pool_in_branches', @db.insert_id)
          end
        end

        t.confirm(t_id)

        st.close

      else # there are snapshots on the destination
        dst_last_snap = st.fetch
        src_last_snap = nil
        transfered_snaps = []
        st.close

        # if branched
        #   select last snapshot from head branch
        if dst_branched?
          st = @db.prepared_st(
              'SELECT s.id, s.name, s.confirmed
              FROM snapshot_in_pool_in_branches sipb
              INNER JOIN snapshots_in_pool sip ON sip.id = sipb.snapshot_in_pool
              INNER JOIN snapshots s ON s.id = sip.snapshot_id
              WHERE sipb.head = 1 AND sipb.dataset_in_pool_id = ?
              ORDER BY s.snapshot_id DESC
              LIMIT 1',
              @dst_dataset_in_pool_id
          )
          dst_last_snap = st.fetch
          st.close
        end

        # select all snapshots from source in reverse order
        st = @db.prepared_st(
            'SELECT s.id, s.name, s.confirmed
            FROM snapshot_in_pools sip
            INNER JOIN snapshots s ON s.id = sip.snapshot_id
            WHERE dataset_in_pool_id = ?
            ORDER BY snapshot_id DESC',
            @src_dataset_in_pool_id
        )

        st.each do |snap|
          src_last_snap ||= snap

          transfered_snaps.insert(0, {
              id: snap[0],
              name: snap[1],
              confirmed: snap[2]
          })

          if dst_last_snap[0] == snap[0] # found the common snapshot
            # incremental send from snap[1] to src_last_snap[1]
            # if they are the same, it is the last snapshot on source and nothing has to be sent
            unless snap[0] == src_last_snap[0]
              t_id = t.prepare({
                  node: @dst_node_id,
                  vps: @vps_id,
                  type: :dataset_transfer
              })

              transfered_snaps.map! do |s|
                @db.prepared(
                    'INSERT INTO snapshot_in_pools (snapshot_id, dataset_in_pool_id, confirmed)
                    VALUES (?, ?, 0)',
                    s[0], @dst_dataset_in_pool_id
                )

                sip_id = @db.insert_id

                t.confirm_create(t_id, 'SnapshotInPool', 'snapshot_in_pools', sip_id)

                # if branched
                #  insert into branch as well
                if dst_branched?
                  @db.prepared(
                      'INSERT INTO snapshot_in_pool_in_branches (snapshot_in_pool_id, branch_id, confirmed)
                      VALUES (?, ?, 0)',
                      sip_id, branch_id
                  )

                  t.confirm_create(t_id, 'SnapshotInPoolInBranches', 'snapshot_in_pool_in_branches', @db.insert_id)
                end
              end

              t.confirm(t_id, {
                  src_node_addr: @src_node_addr,
                  src_pool_fs: @src_pool_fs,
                  dst_pool_fs: @dst_pool_fs,
                  dataset_name: @src_ds_name,
                  snapshots: transfered_snaps
              })

              return
            end
          end
        end

        log "History for #{@src_ds_name} is fucked up, cannot make a transfer"
      end
    end

    def rollback
      # FIXME
    end

    protected
    def dst_branched?
      @dst_pool_role.to_i == 2
    end
  end
end
