module VpsAdmind
  class Commands::Dataset::Set < Commands::Base
    handle 5216

    include Utils::System
    include Utils::Zfs

    def exec
      @properties.each do |k,v|
        zfs(:set, "#{k}=\"#{v}\"", "#{@pool_fs}/#{@name}")
      end
      ok
    end

    def rollback
      ok # FIXME
    end
  end
end
