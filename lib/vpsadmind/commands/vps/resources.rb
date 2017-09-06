module VpsAdmind
  class Commands::Vps::Resources < Commands::Base
    handle 2003
    needs :system, :vz

    def exec
      @resources.each do |r|
        vzctl(:set, @vps_id, translate_value(r['resource'], r['value']), true)
      end

      ok
    end

    def rollback
      @resources.each do |r|
        vzctl(:set, @vps_id, translate_value(r['resource'], r['original']), true)
      end

      ok
    end

    protected
    def translate_value(name, value)
      case name
        when 'cpu'
          {:cpus => value}

        when 'cpu_limit'
          {:cpulimit => value || 0}

        when 'memory'
          {:ram => "#{value}M"}

        when 'swap'
          {:swap => "#{value}M"}
      end
    end
  end
end
