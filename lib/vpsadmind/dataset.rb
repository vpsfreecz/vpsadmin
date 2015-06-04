module VpsAdmind
  class Dataset
    include Utils::Log
    include Utils::System
    include Utils::Zfs

    def set
      zfs(:set, "sharenfs=\"#{@params['share_options']}\"", @params['name']) if @params['share_options']
      zfs(:set, "quota=#{@params['quota'].to_i == 0 ? 'none' : @params['quota']}", @params['name'])
    end

    def destroy(pool_fs, name, recursive)
      zfs(:destroy, recursive ? '-r' : nil, "#{pool_fs}/#{name}")
    end

    def snapshot(pool_fs, dataset_name)
      snap = Time.new.strftime('%Y-%m-%dT%H:%M:%S')
      zfs(:snapshot, nil, "#{pool_fs}/#{dataset_name}@#{snap}")
      snap
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
  end
end
