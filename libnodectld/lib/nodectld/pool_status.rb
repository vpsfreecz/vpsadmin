require 'libosctl'

module NodeCtld
  class PoolStatus
    STATE_VALUES = %i(unknown online degraded suspended faulted error)
    SCAN_VALUES = %i(unknown none scrub resilver error)

    include OsCtl::Lib::Utils::Log

    def init(db)
      @pools = fetch_pools(db)
    end

    def update(db = nil)
      my = db || Db.new
      check_status(my)
      my.close unless db
    end

    protected
    def check_status(db)
      t = Time.now.utc

      begin
        st = OsCtl::Lib::Zfs::ZpoolStatus.new(pools: @pools.values)
      rescue SystemCommandFailed => e
        log(:fatal, :pool_status, e.message)
      end

      @pools.each do |id, name|
        pool_st = st && st[name]

        state = state_to_db(:error)
        scan = state_to_db(:error)

        if pool_st
          state = state_to_db(pool_st.state)
          scan = scan_to_db(pool_st.scan)
        end

        db.prepared(
          'UPDATE pools SET state = ?, scan = ?, checked_at = ? WHERE id = ?',
          state,
          scan,
          t.strftime('%Y-%m-%d %H:%M:%S'),
          id,
        )
      end
    end

    def state_to_db(v)
      STATE_VALUES.index(v) || STATE_VALUES.index(:error)
    end

    def scan_to_db(v)
      SCAN_VALUES.index(v) || SCAN_VALUES.index(:error)
    end

    def fetch_pools(db)
      ret = {}

      db.prepared(
        'SELECT id, filesystem FROM pools WHERE node_id = ?',
        $CFG.get(:vpsadmin, :node_id)
      ).each { |row| ret[row['id']] = row['filesystem'].split('/').first }

      ret
    end
  end
end
