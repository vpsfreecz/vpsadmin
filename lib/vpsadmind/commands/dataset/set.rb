module VpsAdmind
  class Commands::Dataset::Set < Commands::Base
    handle 5216
    needs :system, :zfs

    def exec
      change_properties(1) # new values
      ok
    end

    def rollback
      change_properties(0) # old values
      ok
    end

    protected
    def change_properties(i)
      @properties.each do |k, v|
        zfs(:set, "#{k}=\"#{translate(v[i])}\"", "#{@pool_fs}/#{@name}")
      end
    end

    def translate(v)
      if v === true
        'on'

      elsif v === false
        'off'

      elsif v.nil?
        'none'

      else
        v
      end
    end
  end
end
