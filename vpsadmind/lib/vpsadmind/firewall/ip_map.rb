module VpsAdmind::Firewall
  class IpMap
    IpAddr = Struct.new(:id, :version, :user_id, :monitor) do
      def initialize(*_)
        super

        self.monitor = IpMonitor.new(self)
      end

      def to_h
        ret = super
        ret.delete(:monitor)
        ret
      end
    end

    def initialize
      @mutex = ::Mutex.new
      @map = {}
      @update_queue = Queue.new
    end

    def populate(db)
      sync do
        @map.clear unless @map.empty?

        db.query("
            SELECT ip.id, ip_addr, n.ip_version, vpses.user_id
            FROM ip_addresses ip
            INNER JOIN networks n ON n.id = ip.network_id
            INNER JOIN network_interfaces netifs ON netifs.id = ip.network_interface_id
            INNER JOIN vpses ON vpses.id = netifs.vps_id
            WHERE node_id = #{$CFG.get(:vpsadmin, :server_id)}
        ").each_hash do |ip|
          @map[ip['ip_addr']] = IpAddr.new(
              ip['id'].to_i,
              ip['ip_version'].to_i,
              ip['user_id'].to_i
          )
        end

        update_ipset
      end
    end

    def start
      @thread = Thread.new { run_ipset_in_background }
    end

    def set(addr, id, version, user_id)
      sync do
        @map[addr] = IpAddr.new(id, version, user_id)
        request_ipset_update
      end
    end

    def get(addr)
      sync { @map[addr] }
    end

    def [](*args)
      get(*args)
    end

    def unset(addr)
      sync do
        @map.delete(addr)
        request_ipset_update
      end
    end

    def clear
      sync { @map.clear }
    end

    def dump
      sync { Marshal.load(Marshal.dump(@map)) }
    end

    def synchronize
      if @mutex.owned?
        yield

      else
        @mutex.synchronize { yield }
      end
    end

    alias_method :sync, :synchronize

    protected
    def request_ipset_update
      @update_queue << :update
    end

    def run_ipset_in_background
      loop do
        @update_queue.pop
        update_ipset
        sleep($CFG.get(:vpsadmin, :ipset_update_interval))
      end
    end

    def update_ipset
      sync do
        @update_queue.clear

        [4, 6].each do |v|
          IpSet.create_or_replace!(
            "vpsadmin_v#{v}_local_addrs",
            "hash:ip family #{v == 4 ? 'inet' : 'inet6'}",
            @map.select { |_, n| n.version == v }.keys
          )
        end
      end
    end
  end
end
