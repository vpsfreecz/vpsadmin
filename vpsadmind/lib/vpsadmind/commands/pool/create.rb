module VpsAdmind
  class Commands::Pool::Create < Commands::Base
    handle 5250
    needs :system, :zfs, :pool

    def exec
      if @options
        opts = @options.map { |k, v| "-o #{k}=\"#{translate_property(k, v)}\""  }.join(' ')
      else
        opts = ''
      end

      zfs(:create, opts, @pool_fs)
      zfs(:create, nil, "#{@pool_fs}/#{pool_work_root}")

      pool_working_dirs.each do |s|
        zfs(:create, nil, "#{@pool_fs}/#{path_to_pool_working_dir(s)}")
      end

      ok
    end

    def rollback
      pool_working_dirs.each do |s|
        zfs(:destroy, nil, "#{@pool_fs}/#{path_to_pool_working_dir(s)}", [1])
      end

      zfs(:destroy, nil, "#{@pool_fs}/#{pool_work_root}", [1])
      zfs(:destroy, nil, @pool_fs, [1])
    end
  end
end
