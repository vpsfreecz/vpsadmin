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
      cpu_limits = []

      @resources.each do |r|
        case r['resource']
        when 'cpu'
          # We can't actually assign CPU cores without assigning them statically,
          # so we just set CPU limit
          cpu_limits << (r[key] * 100)

        when 'cpu_limit'
          cpu_limits << r[key] if r[key] && r[key] > 0

        when 'memory'
          mem = r[key]

        when 'swap'
          swap = r[key]
        end
      end

      if mem > 0
        osctl(
          %i[ct set memory-limit],
          [@vps_id, "#{mem}M", swap > 0 ? "#{swap}M" : nil].compact
        )
        osctl(
          %i[ct cgparams set],
          [@vps_id, 'memory.soft_limit_in_bytes', (mem * 0.8 * 1024 * 1024).round],
          { version: '1' }
        )
        osctl(
          %i[ct cgparams set],
          [@vps_id, 'memory.low', (mem * 0.8 * 1024 * 1024).round],
          { version: '2' }
        )
      end

      return unless cpu_limits.any?

      cpu_limit = cpu_limits.min || 0

      if cpu_limit > 0
        osctl(%i[ct set cpu-limit], [@vps_id, cpu_limit.to_s])

      else
        osctl(%i[ct unset cpu-limit], @vps_id)
      end
    end
  end
end
