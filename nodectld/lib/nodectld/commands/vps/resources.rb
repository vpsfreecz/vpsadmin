module NodeCtld
  class Commands::Vps::Resources < Commands::Base
    handle 2003
    needs :system, :osctl

    def exec
      set('value')
      ok
    end

    def rollback
      set('original')
      ok
    end

    protected
    def set(key)
      mem = 0
      swap = 0

      @resources.each do |r|
        case r['resource']
        when 'cpu'
          # TODO: this cannot be done using cgroups afaik, i.e. limit number of
          #       cores and _not_ assign concrete cpus

        when 'cpu_limit'
          # TODO: cpu.cfs_period_us, cpu.cfs_quota_us

        when 'memory'
          mem = r[key]

        when 'swap'
          swap = r[key]
        end
      end

      if mem > 0 && swap > 0
        osctl(
          %i(ct cgparams set),
          [@vps_id, 'memory.limit_in_bytes', mem * 1024 * 1024]
        )
        osctl(
          %i(ct cgparams set),
          [@vps_id, 'memory.memsw.limit_in_bytes', (mem+swap) * 1024 * 1024]
        )

      elsif mem > 0
        osctl(
          %i(ct cgparams unset),
          [@vps_id, 'memory.memsw.limit_in_bytes'],
          {}, {}, valid_rcs: [1]
        )
        osctl(
          %i(ct cgparams set),
          [@vps_id, 'memory.limit_in_bytes', mem * 1024 * 1024]
        )
      end
    end
  end
end
