require 'libosctl'
require 'thread'

module NodeCtld
  class PoolStatus
    STATE_VALUES = %i(unknown online degraded suspended faulted error)
    SCAN_VALUES = %i(unknown none scrub resilver error)

    include OsCtl::Lib::Utils::Log

    def initialize
      @mutex = Mutex.new
      @last_check = Time.now.utc
      @state_summary_value = state_to_db(:unknown)
      @scan_summary_value = scan_to_db(:unknown)
      @scan_percent_summary = nil
    end

    def init(db)
      @pools = fetch_pools(db)
    end

    def update(db = nil)
      my = db || Db.new
      check_status(my)
      my.close unless db
    end

    # @return [Array<Time, Integer, Integer, Float>)]
    #   last check, state, scan and scan percent summary values
    def summary_values
      @mutex.synchronize do
        [@last_check, @state_summary_value, @scan_summary_value, @scan_percent_summary]
      end
    end

    protected
    def check_status(db)
      t = Time.now.utc

      state_summary = state_to_db(:unknown)
      scan_summary = scan_to_db(:unknown)
      scan_percent_summary = nil

      begin
        st = OsCtl::Lib::Zfs::ZpoolStatus.new(pools: @pools.values)
      rescue SystemCommandFailed => e
        log(:fatal, :pool_status, e.message)
      end

      @pools.each do |id, name|
        pool_st = st && st[name]

        state = state_to_db(:error)
        scan = state_to_db(:error)
        scan_percent = nil

        if pool_st
          state = state_to_db(pool_st.state)
          scan = scan_to_db(pool_st.scan)
          scan_percent = pool_st.scan_percent
        end

        state_summary = state if state > state_summary
        scan_summary = scan if scan > scan_summary

        if scan_percent && (scan_percent_summary.nil? || scan_percent < scan_percent_summary)
          scan_percent_summary = scan_percent
        end

        db.prepared(
          'UPDATE pools SET state = ?, scan = ?, scan_percent = ?, checked_at = ? WHERE id = ?',
          state,
          scan,
          scan_percent,
          t.strftime('%Y-%m-%d %H:%M:%S'),
          id,
        )
      end

      @mutex.synchronize do
        @last_check = t
        @state_summary_value = state_summary
        @scan_summary_value = scan_summary
        @scan_percent_summary = scan_percent_summary
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
