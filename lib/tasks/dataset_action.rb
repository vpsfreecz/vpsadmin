module Tasks
  class DatasetAction < Task
    ACTIONS = %i(snapshot transfer rollback)

    def self.query_params(task)
      "SELECT a.*,
        src_ds.name AS src_ds_name, src_ds.id AS src_ds_id,
        src_pool.node_id AS src_node_id, dst_pool.node_id AS dst_node_id,
        src_node.server_ip4 AS src_node_addr,
        src_pool.filesystem AS src_pool_fs, dst_pool.filesystem AS dst_pool_fs,
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
      t.queue({
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
    end

    def transfer
      log "execute dataset_action#transfer #{@src_dataset_in_pool_id}"

      t = Transaction.new(@db)

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

        st.each { |row| all_snapshots << row }

        all_snapshots.each do |snap|
          @db.prepared(
              'INSERT INTO snapshot_in_pools (snapshot_id, dataset_in_pool_id, confirmed)
              VALUES (?, ?, 0)',
              snap[0], @dst_dataset_in_pool_id
          )

          snap << @db.insert_id
        end

        st.close

        t.queue({
            node: @dst_node_id,
            vps: @vps_id,
            type: :dataset_transfer,
            param: {
                src_node_addr: @src_node_addr,
                src_pool_fs: @src_pool_fs,
                dst_pool_fs: @dst_pool_fs,
                dataset_name: @src_ds_name,
                snapshots: all_snapshots,
                initial: true
            }
        })

      else # there are snapshots on the destination
        dst_last_snap = st.fetch
        src_last_snap = nil
        transfered_snaps = []
        st.close

        # select last snapshot from source
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

          transfered_snaps.insert(0, snap)

          if dst_last_snap[0] == snap[0] # found the common snapshot
            # incremental send from snap[1] to src_last_snap[1]
            # if they are the same, it is the last snapshot on source and nothing has to be sent
            unless snap[0] == src_last_snap[0]
              transfered_snaps.map! do |s|
                @db.prepared(
                    'INSERT INTO snapshot_in_pools (snapshot_id, dataset_in_pool_id, confirmed)
                    VALUES (?, ?, 0)',
                    s[0], @dst_dataset_in_pool_id
                )

                s << @db.insert_id
              end

              t.queue({
                  node: @dst_node_id,
                  vps: @vps_id,
                  type: :dataset_transfer,
                  param: {
                      src_node_addr: @src_node_addr,
                      src_pool_fs: @src_pool_fs,
                      dst_pool_fs: @dst_pool_fs,
                      dataset_name: @src_ds_name,
                      snapshots: transfered_snaps
                  }
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
  end
end
