module VpsAdmind
  class Commands::Dataset::Set < Commands::Base
    handle 5216

    include Utils::System
    include Utils::Zfs

    def exec
      @properties.each do |k,v|
        zfs(:set, "#{k}=\"#{translate(v)}\"", "#{@pool_fs}/#{@name}")
      end

      ok
    end

    def rollback
      ok # FIXME
    end

    protected
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
