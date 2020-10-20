module VpsAdmind
  class Shaper
    include Utils::Log
    include Utils::System

    @@mutex = ::Mutex.new

    def init(db)
      @@mutex.synchronize do
        safe_init(db)
      end
    end

    def flush
      @@mutex.synchronize do
        safe_flush
      end
    end

    def reinit(db)
      @@mutex.synchronize do
        safe_flush
        safe_init(db)
      end
    end

    def root_change(max_tx, max_rx)
      @@mutex.synchronize do
        shape_root(
            max_tx,
            max_rx
        )
      end
    end

    def shape_set(addr, version, shaper)
      @@mutex.synchronize do
        shape_ip(
            addr,
            version,
            shaper['class_id'],
            shaper['max_tx'],
            shaper['max_rx']
        )
      end
    end

    def shape_change(addr, version, shaper)
      @@mutex.synchronize do
        change_shaper(
            addr,
            version,
            shaper['class_id'],
            shaper['max_tx'],
            shaper['max_rx']
        )
      end
    end

    def shape_unset(addr, version, shaper)
      @@mutex.synchronize do
        free_ip(
            addr,
            version,
            shaper['class_id']
        )
      end
    end

    protected
    def safe_init(db)
      devs = $CFG.get(:vpsadmin, :net_interfaces)
      tx = $CFG.get(:vpsadmin, :max_tx)
      rx = $CFG.get(:vpsadmin, :max_rx)

      return if devs.empty?

      devs.each do |dev|
        tc("qdisc add dev #{dev} root handle 1: htb", [2])
      end

      tc('qdisc add dev venet0 root handle 1: htb', [2])

      tc("class add dev venet0 parent 1: classid 1:1 htb rate #{rx}bps ceil #{rx}bps burst 1M", [2])

      devs.each do |dev|
        tc("class add dev #{dev} parent 1: classid 1:1 htb rate #{tx}bps ceil #{tx}bps burst 1M", [2])
      end

      all_ips(db) do |ip|
        devs.each do |dev|
          shape_ip(ip['ip_addr'], ip['ip_version'].to_i, ip['class_id'], ip['max_tx'], ip['max_rx'], dev)
        end
      end
    end

    def safe_flush
      devs = $CFG.get(:vpsadmin, :net_interfaces)

      devs.each { |dev| tc("qdisc del dev #{dev} root handle 1:", [2]) }
      tc('qdisc del dev venet0 root handle 1:', [2])
    end

    def shape_root(tx, rx)
      devs = $CFG.get(:vpsadmin, :net_interfaces)

      ret_in = tc("class change dev venet0 parent 1: classid 1:1 htb rate #{rx}bps ceil #{rx}bps burst 1M", [2])

      ret_outs = devs.map do |dev|
        tc("class change dev #{dev} parent 1: classid 1:1 htb rate #{tx}bps ceil #{tx}bps burst 1M", [2])
      end

      if ret_in[:exitstatus] == 2 || ret_outs.detect { |ret| ret[:exitstatus] == 2 }
        safe_init(Db.new)
      end
    end

    def shape_ip(addr, v, class_id, tx, rx, dev = nil)
      devs ||= $CFG.get(:vpsadmin, :net_interfaces)

      return if devs.empty? || tx == 0 || rx == 0 # it ain't perfect

      tc("class add dev venet0 parent 1:1 classid 1:#{class_id} htb rate #{rx}bps ceil #{rx}bps burst 300k", [2])

      devs.each do |dev|
        tc("class add dev #{dev} parent 1:1 classid 1:#{class_id} htb rate #{tx}bps ceil #{tx}bps burst 300k", [2])
        add_filters(addr, v, class_id, dev)
        tc("qdisc add dev #{dev} parent 1:#{class_id} handle #{class_id}: sfq perturb 10", [2])
      end

      tc("qdisc add dev venet0 parent 1:#{class_id} handle #{class_id}: sfq perturb 10", [2])
    end

    def change_shaper(addr, v, class_id, tx, rx)
      devs ||= $CFG.get(:vpsadmin, :net_interfaces)

      return if devs.empty?

      if tx == 0 || rx == 0
        free_ip(addr, v, class_id)

      else
        ret_in = tc("class change dev venet0 parent 1:1 classid 1:#{class_id} htb rate #{rx}bps ceil #{rx}bps burst 300k", [2])

        ret_outs = devs.map do |dev|
          tc("class change dev #{dev} parent 1:1 classid 1:#{class_id} htb rate #{tx}bps ceil #{tx}bps burst 300k", [2])
        end

        # either one of those commands reported 'RTNETLINK answers: No such file or directory'
        if ret_in[:exitstatus] == 2 || ret_outs.detect { |ret| ret[:exitstatus] == 2 }
          shape_ip(addr, v, class_id, rx, tx, dev)
        end
      end
    end

    def add_filters(addr, v, class_id, dev)
      if v == 4
        proto = 'ip'
        match = 'ip'
        prio = 16

      else
        proto = 'ipv6'
        match = 'ip6'
        prio = 17
      end

      tc("filter add dev venet0 parent 1: protocol #{proto} prio #{prio} u32 match #{match} dst #{addr} flowid 1:#{class_id}", [2])
      tc("filter add dev #{dev} parent 1: protocol #{proto} prio #{prio} u32 match #{match} src #{addr} flowid 1:#{class_id}", [2])
    end

    def free_ip(addr, v, class_id)
      devs = $CFG.get(:vpsadmin, :net_interface)

      return if devs.empty?

      devs.each do |dev|
        tc("qdisc del dev #{dev} parent 1:#{class_id} handle #{class_id}:", [2])
      end

      tc("qdisc del dev venet0 parent 1:#{class_id} handle #{class_id}:", [2])

      # deletes all filters, impossible to delete just one
      tc('filter del dev venet0 parent 1: protocol ip prio 16', [2])

      devs.each do |dev|
        tc("filter del dev #{dev} parent 1: protocol ip prio 16", [2])
      end

      tc("class del dev venet0 parent 1:1 classid 1:#{class_id}", [2])

      devs.each do |dev|
        tc("class del dev #{dev} parent 1:1 classid 1:#{class_id}", [2])
      end

      # since all filters were deleted, set them up again
      all_ips(Db.new) do |ip|
        devs.each do |dev|
          add_filters(ip['ip_addr'], ip['ip_version'].to_i, ip['class_id'], dev)
        end
      end
    end

    def all_ips(db)
      rs = db.query("SELECT ip_addr, ip_version, class_id, max_tx, max_rx
                    FROM vpses
                    INNER JOIN network_interfaces netifs ON netifs.vps_id = vpses.id
                    INNER JOIN ip_addresses ip ON ip.network_interface_id = netifs.id
                    INNER JOIN networks n ON n.id = ip.network_id
                    WHERE vpses.node_id = #{$CFG.get(:vpsadmin, :server_id)}")
      rs.each_hash do |ip|
        yield ip
      end
    end

    def tc(arg, valid_rcs=[])
      syscmd("#{$CFG.get(:bin, :tc)} #{arg}", valid_rcs)
    end
  end
end
