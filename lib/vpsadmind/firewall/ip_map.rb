module VpsAdmind
  class Firewall
    class IpMap
      IpAddr = Struct.new(:id, :user_id)

      def initialize
        @mutex = ::Mutex.new
        @map = {}
      end

      def populate(db)
        sync do
          @map.clear unless @map.empty?

          db.query("
              SELECT ip_id, ip_addr, vps.m_id
              FROM vps_ip
              INNER JOIN vps ON vps.vps_id = vps_ip.vps_id
              WHERE vps_server = #{$CFG.get(:vpsadmin, :server_id)}
          ").each_hash do |ip|
            @map[ip['ip_addr']] = IpAddr.new(ip['ip_id'].to_i, ip['m_id'].to_i)
          end
        end
      end

      def set(addr, id, user_id)
        sync { @map[addr] = IpAddr.new(id, user_id) }
      end

      def get(addr)
        sync { @map[addr] }
      end

      def [](*args)
        get(*args)
      end

      def unset(addr)
        sync { @map.delete(addr) }
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
    end
  end
end
