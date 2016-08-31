module VpsAdmind
  class Firewall
    include Utils::Log
    include Utils::System

    CHAIN = 'accounting'
    PROTOCOLS = [:tcp, :udp, :all]

    @@mutex = ::Mutex.new

    def init(db)
      res = {}

      [4, 6].each do |v|
        ret = iptables(v, {:N => CHAIN}, [1,])

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

    def flush(db = nil)
      created = false

      unless db
        db = Db.new
        created = true
      end

      update_traffic(db)
      cleanup

      db.close if created
    end

    def reinit(db = nil)
      created = false

      unless db
        db = Db.new
        created = true
      end

      update_traffic(db)
      cleanup
      r = init(db)

      db.close if created
      r
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
      Firewall.mutex.synchronize do
        @params['ip_addrs'].each do |ip|
          reg_ip(ip['addr'], ip['ver'])
        end
      end

      ok
    end

    def read_traffic
      ret = {}

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

      ret
    end

    def update_traffic(db)
      read_traffic.each do |ip, traffic|
        traffic.each do |proto, t|
          next if t[:packets][:in] == 0 && t[:packets][:out] == 0

          db.prepared('INSERT INTO transfered_recent SET
                        tr_ip = ?, tr_proto = ?,
                        tr_packets_in = ?, tr_packets_out = ?,
                        tr_bytes_in = ?, tr_bytes_out = ?,
                        tr_date = NOW()
                       ON DUPLICATE KEY UPDATE
                        tr_packets_in = tr_packets_in + values(tr_packets_in),
                        tr_packets_out = tr_packets_out + values(tr_packets_out),
                        tr_bytes_in = tr_bytes_in + values(tr_bytes_in),
                        tr_bytes_out = tr_bytes_out + values(tr_bytes_out)',
                      ip, proto.to_s,
                      t[:packets][:in], t[:packets][:out],
                      t[:bytes][:in], t[:bytes][:out]
          )
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

    def iptables(ver, opts, valid_rcs = [])
      options = []

      if opts.instance_of?(Hash)
        opts.each do |k, v|
          k = k.to_s
          options << "#{k.start_with?("-") ? "" : (k.length > 1 ? "--" : "-")}#{k}#{v ? " " : ""}#{v}"
        end
      elsif opts.instance_of?(Array)
        options = opts
      else
        options << opts
      end

      try_cnt = 0

      begin
        syscmd("#{$CFG.get(:bin, ver == 4 ? :iptables : :ip6tables)} #{options.join(" ")}", valid_rcs)

      rescue CommandFailed => err
        if err.rc == 1 && err.output =~ /Resource temporarily unavailable/
          if try_cnt == 3
            log 'Run out of tries'
            raise err
          end

          log "#{err.cmd} failed with error 'Resource temporarily unavailable', retrying in 3 seconds"

          try_cnt += 1
          sleep(3)
          retry
        else
          raise err
        end
      end
    end

    def Firewall.mutex
      @@mutex
    end
  end
end
