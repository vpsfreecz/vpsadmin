module VpsAdmind
  class Firewall
    class Accounting
      include VpsAdmind::Utils::Log
      include VpsAdmind::Utils::System
      include VpsAdmind::Utils::Iptables
      
      CHAIN = 'accounting'
      PROTOCOLS = [:tcp, :udp, :all]
      PROTOCOL_MAP = [:all, :tcp, :udp]

      attr_reader :fw

      def initialize(fw)
        @fw = fw
      end

      def init(db)
        res = {}

        [4, 6].each do |v|
          ret = iptables(v, {:N => CHAIN}, valid_rcs: [1,])

          # Chain already exists, we don't have to continue
          if ret[:exitstatus] == 1
            log "Skipping init for IPv#{v}, chain #{CHAIN} already exists"
            next
          end

          iptables(v, {:Z => CHAIN})
          iptables(v, {:A => 'FORWARD', :j => CHAIN})
          
          rs = db.query("SELECT ip_addr
                        FROM vps_ip
                        INNER JOIN vps ON vps.vps_id = vps_ip.vps_id
                        INNER JOIN networks n ON n.id = vps_ip.network_id
                        WHERE vps_server = #{$CFG.get(:vpsadmin, :server_id)}
                        AND n.ip_version = #{v}")
          rs.each_hash do |ip|
            reg_ip(ip['ip_addr'], v)
          end

          res[v] = rs.num_rows
          log "Tracking #{res[v]} IPv#{v} addresses"
        end

        res
      end
    
      def reg_ip(addr, v)
        PROTOCOLS.each do |p|
          iptables(v, ['-A', CHAIN, '-s', addr, '-p', p.to_s, '-j', 'ACCEPT'])
          iptables(v, ['-A', CHAIN, '-d', addr, '-p', p.to_s, '-j', 'ACCEPT'])
        end
      end

      def unreg_ip(addr, v)
        PROTOCOLS.each do |p|
          iptables(v, ['-D', CHAIN, '-s', addr, '-p', p.to_s, '-j', 'ACCEPT'])
          iptables(v, ['-D', CHAIN, '-d', addr, '-p', p.to_s, '-j', 'ACCEPT'])
        end
      end

      def reg_ips
        @fw.synchronize do
          @params['ip_addrs'].each do |ip|
            reg_ip(ip['addr'], ip['ver'])
          end
        end

        ok
      end

      def read_traffic
        ret = {}

        @fw.synchronize do
          {4 => '0.0.0.0/0', 6 => '::/0'}.each do |v, all|
            iptables(v, ['-L', CHAIN, '-nvx', '-Z'])[:output].split("\n")[2..-2].each do |l|
              fields = l.strip.split(/\s+/)
              src = fields[v == 4 ? 7 : 6]
              dst = fields[v == 4 ? 8 : 7]
              ip = src == all ? dst : src
              proto = fields[3].to_sym

              if v == 6
                ip = ip.split('/').first
              end

              ret[ip] ||= {}
              ret[ip][proto] ||= {:bytes => {}, :packets => {}}
              ret[ip][proto][:packets][src == all ? :in : :out] = fields[0].to_i
              ret[ip][proto][:bytes][src == all ? :in : :out] = fields[1].to_i
            end
          end
        end

        ret
      end

      def update_traffic(db)
        read_traffic.each do |ip, traffic|
          @fw.ip_map.synchronize do
            traffic.each do |proto, t|
              next if t[:packets][:in] == 0 && t[:packets][:out] == 0
              
              addr = @fw.ip_map[ip]

              unless addr
                log(:warn, :firewall, "IP '#{ip}' not found in IP map")
                next
              end

              db.prepared(
                  'INSERT INTO ip_recent_traffics SET
                    ip_address_id = ?, user_id = ?, protocol = ?,
                    packets_in = ?, packets_out = ?,
                    bytes_in = ?, bytes_out = ?,
                    created_at = NOW()
                  ON DUPLICATE KEY UPDATE
                    packets_in = packets_in + values(packets_in),
                    packets_out = packets_out + values(packets_out),
                    bytes_in = bytes_in + values(bytes_in),
                    bytes_out = bytes_out + values(bytes_out)',
                  addr.id, addr.user_id, PROTOCOL_MAP.index(proto),
                  t[:packets][:in], t[:packets][:out],
                  t[:bytes][:in], t[:bytes][:out]
              )
            end
          end
        end

      rescue CommandFailed => err
        log(:critical, :firewall, "Failed to update traffic accounting: #{err.output}")
      end

      def reset_traffic_counter
        [4, 6].each do |v|
          iptables(v, {:Z => CHAIN})
        end
      end

      def cleanup
        [4, 6].each do |v|
          iptables(v, {:F => CHAIN})
          iptables(v, {:D => 'FORWARD', :j => CHAIN})
          iptables(v, {:X => CHAIN})
        end
      end
    end
  end
end
