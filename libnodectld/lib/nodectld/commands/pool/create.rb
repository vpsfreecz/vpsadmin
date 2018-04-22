module NodeCtld
  class Commands::Pool::Create < Commands::Base
    handle 5250
    needs :system, :zfs, :pool

    def exec
      ensure_ds(@pool_fs, @options)
      ensure_ds("#{@pool_fs}/#{pool_work_root}")

      pool_working_dirs.each do |s|
        ensure_ds("#{@pool_fs}/#{path_to_pool_working_dir(s)}")
      end

      ok
    end

    def rollback
      pool_working_dirs.each do |s|
        zfs(:destroy, nil, "#{@pool_fs}/#{path_to_pool_working_dir(s)}", valid_rcs: [1])
      end

      zfs(:destroy, nil, "#{@pool_fs}/#{pool_work_root}", valid_rcs: [1])
      zfs(:destroy, nil, @pool_fs, valid_rcs: [1])
    end

    protected
    def ensure_ds(fs, opts = nil)
      ret = zfs(:get, '-H -o value name', fs, valid_rcs: [1])

      # Does not exist
      if ret[:exitstatus] == 1
        if opts
          str_opts = opts.map { |k, v| "-o #{k}=\"#{translate_property(k, v)}\""  }.join(' ')
        else
          str_opts = ''
        end

        zfs(:create, str_opts, fs)
        return
      end

      # Exists, set options
      return unless opts

      str_opts = opts.map { |k, v| "#{k}=\"#{translate_property(k, v)}\""  }.join(' ')
      return if str_opts.empty?

      zfs(:set, str_opts, fs)
    end
  end
end
