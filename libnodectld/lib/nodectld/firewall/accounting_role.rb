require 'libosctl'
require 'nodectld/utils'
require 'nodectld/exceptions'

module NodeCtld::Firewall
  class AccountingRole
    include OsCtl::Lib::Utils::Log
    include NodeCtld::Utils::System
    include NodeCtld::Utils::Iptables

    PROTOCOLS = [:tcp, :udp, :all]
    PROTOCOL_MAP = [:all, :tcp, :udp]

    attr_reader :role, :chain

    def initialize(fw, r)
      @fw = fw
      @role = r
      @chain = "vpsadmin_accounting_#{r}"
    end

    def init(db, v)
      ret = iptables(v, {N: chain}, valid_rcs: [1,])

      # Chain already exists, we don't have to continue
      if ret[:exitstatus] == 1
        log "Skipping init for IPv#{v}, chain #{chain} already exists"
        return
      end

      iptables(v, {Z: chain})

      rs = db.query("SELECT ip.ip_addr, ip.prefix
                    FROM ip_addresses ip
                    INNER JOIN network_interfaces netifs ON netifs.id = ip.network_interface_id
                    INNER JOIN vpses ON vpses.id = netifs.vps_id
                    INNER JOIN networks n ON n.id = ip.network_id
                    WHERE node_id = #{$CFG.get(:vpsadmin, :node_id)}
                    AND n.ip_version = #{v}
                    AND n.role IN (0, 1)")
      rs.each do |ip|
        reg_ip(ip['ip_addr'], ip['prefix'], v)
      end

      log("#{role} accounting for #{rs.count} IPv#{v} addresses")
    end

    def reg_ip(addr, prefix, v)
      PROTOCOLS.each do |p|
        iptables(v, ['-A', chain, '-s', "#{addr}/#{prefix}", '-p', p.to_s, '-j', 'ACCEPT'])
        iptables(v, ['-A', chain, '-d', "#{addr}/#{prefix}", '-p', p.to_s, '-j', 'ACCEPT'])
      end
    end

    def unreg_ip(addr, prefix, v)
      PROTOCOLS.each do |p|
        iptables(v, ['-D', chain, '-s', "#{addr}/#{prefix}", '-p', p.to_s, '-j', 'ACCEPT'])
        iptables(v, ['-D', chain, '-d', "#{addr}/#{prefix}", '-p', p.to_s, '-j', 'ACCEPT'])
      end
    end

    def read_traffic
      ret = {}

      @fw.synchronize do
        {4 => '0.0.0.0/0', 6 => '::/0'}.each do |v, all|
          iptables(v, ['-L', chain, '-nvx', '-Z'])[:output].split("\n")[2..-2].each do |l|
            fields = l.strip.split(/\s+/)
            src = fields[v == 4 ? 7 : 6]
            dst = fields[v == 4 ? 8 : 7]
            ip = (src == all ? dst : src).split('/').first
            proto = fields[3].to_sym

            ret[ip] ||= {}
            ret[ip][proto] ||= {bytes: {}, packets: {}}
            ret[ip][proto][:packets][src == all ? :in : :out] = fields[0].to_i
            ret[ip][proto][:bytes][src == all ? :in : :out] = fields[1].to_i
          end
        end
      end

      ret
    end

    def update_traffic
      read_traffic.each do |ip, traffic|
        traffic.each do |proto, t|
          yield(ip, proto, t)
        end
      end

    rescue NodeCtld::SystemCommandFailed => err
      log(:critical, :firewall, "Failed to update traffic accounting: #{err.output}")
    end

    def reset_traffic_counter
      [4, 6].each do |v|
        iptables(v, {Z: chain})
      end
    end

    def cleanup
      [4, 6].each do |v|
        iptables(v, {F: chain})
        iptables(v, {X: chain})
      end
    end

    def log_type
      "ipacc=#{role}"
    end
  end
end
