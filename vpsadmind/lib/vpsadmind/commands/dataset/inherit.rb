module VpsAdmind
  class Commands::Dataset::Inherit < Commands::Base
    handle 5219
    needs :system, :zfs

    def exec
      @properties.keys.each do |p|
        zfs(:inherit, p, "#{@pool_fs}/#{@name}")
      end

      ok
    end

    def rollback
      call_cmd(Commands::Dataset::Set, {
          :pool_fs => @pool_fs,
          :name => @name,
          :properties => @properties.merge(@properties) { |_, v| [nil, v] }
      })
    end
  end
end
