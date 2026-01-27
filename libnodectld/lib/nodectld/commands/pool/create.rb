module NodeCtld
  class Commands::Pool::Create < Commands::Base
    handle 5250
    needs :system, :zfs, :pool, :osctl

    def exec
      ensure_ds(@pool_fs, @options)
      ensure_ds("#{@pool_fs}/#{pool_work_root}")

      pool_working_dirs.each do |s|
        ensure_ds("#{@pool_fs}/#{path_to_pool_working_dir(s)}")
      end

      vps_config = File.join('/', @pool_fs, path_to_pool_working_dir(:config), 'vps')
      FileUtils.mkdir_p(vps_config)

      OsCtlUsers.add_pool(@pool_fs)

      grant_device_access

      Daemon.instance.refresh_pools

      ok
    end

    def rollback
      pool_working_dirs.each do |s|
        zfs(:destroy, nil, "#{@pool_fs}/#{path_to_pool_working_dir(s)}", valid_rcs: [1])
      end

      zfs(:destroy, nil, "#{@pool_fs}/#{pool_work_root}", valid_rcs: [1])
      zfs(:destroy, nil, @pool_fs, valid_rcs: [1])

      revoke_device_access

      Daemon.instance.refresh_pools
    end

    protected

    def ensure_ds(fs, opts = nil)
      ret = zfs(:get, '-H -o value name', fs, valid_rcs: [1])

      # Does not exist
      if ret.exitstatus == 1
        str_opts = if opts
                     opts.map { |k, v| "-o #{k}=\"#{translate_property(k, v)}\"" }.join(' ')
                   else
                     ''
                   end

        zfs(:create, str_opts, fs)
        return
      end

      # Exists, set options
      return unless opts

      str_opts = opts.map { |k, v| "#{k}=\"#{translate_property(k, v)}\"" }.join(' ')
      return if str_opts.empty?

      zfs(:set, str_opts, fs)
    end

    def grant_device_access
      pool_devices.each do |ident, devnode|
        osctl(
          %i[group devices add],
          ['/default', *ident, 'rwm', devnode],
          {
            parents: true,
            inherit: false
          }
        )
      rescue SystemCommandFailed => e
        raise if e.rc != 1 || /device already exists/ !~ e.output
      end
    end

    def revoke_device_access
      # rubocop:disable Style/HashEachMethods
      pool_devices.each do |ident, _devnode|
        osctl(
          %i[group devices del],
          ['/default', *ident],
          {},
          {},
          valid_rcs: [1]
        )
      end
      # rubocop:enable Style/HashEachMethods
    end

    def pool_devices
      [
        [%w[char 10 200], '/dev/net/tun'],
        [%w[char 10 229], '/dev/fuse'],
        [%w[char 108 0], '/dev/ppp'],
        [%w[char 10 232], '/dev/kvm']
      ]
    end
  end
end
