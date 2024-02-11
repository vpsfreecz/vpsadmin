require 'libosctl'
require 'thread'

module NodeCtld
  class PoolStatus
    STATES = %i[unknown online degraded suspended faulted error]
    SCANS = %i[unknown none scrub resilver error]

    include OsCtl::Lib::Utils::Log

    def initialize
      @mutex = Mutex.new
      @last_check = Time.now.utc
      @state_summary_value = :unknown
      @scan_summary_value = :unknown
      @scan_percent_summary = nil

      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
    end

    def init
      @pools = fetch_pools
    end

    def update
      return if @pools.empty?

      check_status
    end

    # @return [Array<Time, Integer, Integer, Float>)]
    #   last check, state, scan and scan percent summary values
    def summary_values
      @mutex.synchronize do
        [@last_check, @state_summary_value, @scan_summary_value, @scan_percent_summary]
      end
    end

    protected

    def check_status
      t = Time.now.utc

      state_summary = :unknown
      scan_summary = :unknown
      scan_percent_summary = nil

      begin
        st = OsCtl::Lib::Zfs::ZpoolStatus.new(pools: @pools.values.uniq)
      rescue SystemCommandFailed => e
        log(:fatal, :pool_status, e.message)
      end

      @pools.each do |id, name|
        pool_st = st && st[name]

        state = :error
        scan = :error
        scan_percent = nil

        if pool_st
          state = pool_st.state
          scan = pool_st.scan
          scan_percent = pool_st.scan_percent
        end

        state_summary = state if STATES.index(state) > STATES.index(state_summary)
        scan_summary = scan if SCANS.index(scan) > SCANS.index(scan_summary)

        if scan_percent && (scan_percent_summary.nil? || scan_percent < scan_percent_summary)
          scan_percent_summary = scan_percent
        end

        NodeBunny.publish_drop(
          @exchange,
          {
            id:,
            time: t.to_i,
            state:,
            scan:,
            scan_percent:
          }.to_json,
          content_type: 'application/json',
          routing_key: 'pool_statuses'
        )
      end

      @mutex.synchronize do
        @last_check = t
        @state_summary_value = state_summary
        @scan_summary_value = scan_summary
        @scan_percent_summary = scan_percent_summary
      end
    end

    def fetch_pools
      ret = {}

      RpcClient.run do |rpc|
        rpc.list_pools.each do |pool|
          ret[pool['id']] = pool['name']
        end
      end

      ret
    end
  end
end
