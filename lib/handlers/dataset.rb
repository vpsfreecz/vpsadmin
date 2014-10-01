class Dataset < Executor
  include ZfsUtils

  def create
    zfs(:create, '-p', "#{@params['pool_fs']}/#{@params['name']}")
  end

  def set
    zfs(:set, "sharenfs=\"#{@params['share_options']}\"", @params['name']) if @params['share_options']
    zfs(:set, "quota=#{@params['quota'].to_i == 0 ? 'none' : @params['quota']}", @params['name'])
  end

  def destroy
    zfs(:destroy, @params['recursive'] ? '-r' : nil, "#{@params['pool_fs']}/#{@params['name']}")
  end

  def snapshot
    snap = Time.new.strftime('%Y-%m-%dT%H:%M:%S')

    zfs(:snapshot, nil, "#{@params['pool']}/#{@params['dataset_name']}@#{snap}")

    db = Db.new
    db.prepared('UPDATE snapshots SET name = ? WHERE id = ?', snap, @params['snapshot_id'])
    db.close

    ok
  end

  # Transfer snapshots from src to dst node.
  # Called on the destination node.
  def transfer
    db = Db.new

    snap1 = confirmed_snapshot_name(db, @params['snapshots'].first)
    snap2 = @params['snapshots'].count > 1 ? confirmed_snapshot_name(db, @params['snapshots'].last) : nil

    db.close

    do_transfer(snap1) if @params['initial']
    do_transfer(snap1, snap2) if snap2

    ok
  end

  def rollback

  end

  def clone
    zfs(:clone, nil, "#{}")
  end

  def update_status
    db = Db.new
    rs = db.query(
        "SELECT p.filesystem, ds.name, dip.id
        FROM pools p
        INNER JOIN dataset_in_pools dip ON dip.pool_id = p.id
        INNER JOIN datasets ds ON ds.id = dip.dataset_id
        WHERE p.node_id = #{$CFG.get(:vpsadmin, :server_id)}
        "
    )

    rs.each_hash do |ds|
      used = avail = 0

      get = zfs(:get, '-H -p -o property,value used,available', "#{ds['filesystem']}/#{ds['name']}", [1,])

      next if get[:exitstatus] == 1

      get[:output].split("\n").each do |prop|
        p = prop.split

        case p[0]
          when 'used' then
            used = p[1]
          when 'available' then
            avail = p[1]
        end
      end

      db.prepared(
          'UPDATE dataset_in_pools SET used = ?, avail = ? WHERE id = ?',
          used, avail, ds['id'].to_i
      )
    end
  end

  protected
  def do_transfer(snap1, snap2 = nil)
    recv = "zfs recv -F #{@params['dst_pool_fs']}/#{@params['dataset_name']}"

    if snap2
      send = "zfs send -I #{@params['src_pool_fs']}/#{@params['dst_pool_fs']}@#{snap1} #{@params['src_pool_fs']}/#{@params['dataset_name']}@#{snap2}"
    else
      send = "zfs send #{@params['src_pool_fs']}/#{@params['dst_pool_fs']}@#{snap1}"
    end

    syscmd("ssh #{@params['src_node_addr']} #{send} | #{recv}")
  end

  def confirmed_snapshot_name(db, snap)
    return snap[:name] if snap[:confirmed]

    st = db.prepared_st('SELECT name FROM snapshots WHERE id = ?', snap[:id])
    ret = st.fetch
    st.close

    ret[0]
  end
end
