class Shaper < Executor
  def init(db)
    dev = $CFG.get(:vpsadmin, :netdev)
    tx = $CFG.get(:vpsadmin, :max_tx)
    rx = $CFG.get(:vpsadmin, :max_rx)

    tc("qdisc add dev #{dev} root handle 1: htb", [2])
    tc('qdisc add dev venet0 root handle 1: htb', [2])

    tc("class add dev venet0 parent 1: classid 1:1 htb rate #{rx}bps ceil #{rx}bps burst 1M", [2])
    tc("class add dev #{dev} parent 1: classid 1:1 htb rate #{tx}bps ceil #{tx}bps burst 1M", [2])

    all_ips(db) do |ip|
      shape_ip(ip['ip_addr'], ip['ip_v'].to_i, ip['class_id'], ip['max_tx'], ip['max_rx'], dev)
    end
  end

  def shape_set
    shape_ip(
        @params['addr'],
        @params['version'],
        @params['shaper']['class_id'],
        @params['shaper']['max_tx'],
        @params['shaper']['max_rx']
    )
    ok
  end

  def shape_change
    change_shaper(
        @params['addr'],
        @params['version'],
        @params['shaper']['class_id'],
        @params['shaper']['max_tx'],
        @params['shaper']['max_rx']
    )
    ok
  end

  def shape_unset
    free_ip(
        @params['addr'],
        @params['version'],
        @params['shaper']['class_id']
    )
    ok
  end

  protected
  def shape_ip(addr, v, class_id, tx, rx, dev = nil)
    dev ||= $CFG.get(:vpsadmin, :netdev)

    return if v == 6 || dev.nil? || tx == 0 || rx == 0 # it ain't perfect

    tc("class add dev venet0 parent 1:1 classid 1:#{class_id} htb rate #{rx}bps ceil #{rx}bps burst 300k", [2])
    tc("class add dev #{dev} parent 1:1 classid 1:#{class_id} htb rate #{tx}bps ceil #{tx}bps burst 300k", [2])

    add_filters(addr, v, class_id, dev)

    tc("qdisc add dev #{dev} parent 1:#{class_id} handle #{class_id}: sfq perturb 10", [2])
    tc("qdisc add dev venet0 parent 1:#{class_id} handle #{class_id}: sfq perturb 10", [2])
  end

  def change_shaper(addr, v, class_id, tx, rx)
    dev ||= $CFG.get(:vpsadmin, :netdev)

    return if v == 6 || dev.nil?

    if tx == 0 || rx == 0
      free_ip(addr, v, class_id)

    else
      ret_in = tc("class change dev venet0 parent 1:1 classid 1:#{class_id} htb rate #{rx}bps ceil #{rx}bps burst 300k", [2])
      ret_out = tc("class change dev #{dev} parent 1:1 classid 1:#{class_id} htb rate #{tx}bps ceil #{tx}bps burst 300k", [2])

      # either one of those commands reported 'RTNETLINK answers: No such file or directory'
      if ret_in[:exitstatus] == 2 || ret_out[:exitstatus] == 2
        shape_ip(addr, v, class_id, rx, tx, dev)
      end
    end
  end

  def add_filters(addr, v, class_id, dev)
    return if v == 6

    tc("filter add dev venet0 parent 1: protocol ip prio 16 u32 match ip dst #{addr} flowid 1:#{class_id}", [2])
    tc("filter add dev #{dev} parent 1: protocol ip prio 16 u32 match ip src #{addr} flowid 1:#{class_id}", [2])
  end

  def free_ip(addr, v, class_id)
    dev = $CFG.get(:vpsadmin, :netdev)

    return if v == 6 || dev.nil?

    tc("qdisc del dev #{dev} parent 1:#{class_id} handle #{class_id}:", [2])
    tc("qdisc del dev venet0 parent 1:#{class_id} handle #{class_id}:", [2])

    # deletes all filters, impossible to delete just one
    tc('filter del dev venet0 parent 1: protocol ip prio 16', [2])
    tc("filter del dev #{dev} parent 1: protocol ip prio 16", [2])

    tc("class del dev venet0 parent 1:1 classid 1:#{class_id}", [2])
    tc("class del dev #{dev} parent 1:1 classid 1:#{class_id}", [2])

    # since all filters were deleted, set them up again
    all_ips(Db.new) do |ip|
      add_filters(ip['ip_addr'], ip['ip_v'], ip['class_id'], dev)
    end
  end

  def all_ips(db)
    rs = db.query("SELECT ip_addr, ip_v, class_id, max_tx, max_rx
                  FROM vps_ip, vps
                  WHERE vps_server = #{$CFG.get(:vpsadmin, :server_id)}
                    AND vps_ip.vps_id = vps.vps_id")
    rs.each_hash do |ip|
      yield ip
    end
  end

  def tc(arg, valid_rcs=[])
    syscmd("#{$CFG.get(:bin, :tc)} #{arg}", valid_rcs)
  end
end
