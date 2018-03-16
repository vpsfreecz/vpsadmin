module NodeCtld
  class Dataset
    include OsCtl::Lib::Utils::Log
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
      t = Time.now.utc
      snap = t.strftime('%Y-%m-%dT%H:%M:%S')
      zfs(:snapshot, nil, "#{pool_fs}/#{dataset_name}@#{snap}")
      [snap, t]
    end

    def rollback

    end

    def clone
      zfs(:clone, nil, "#{}")
    end
  end
end
