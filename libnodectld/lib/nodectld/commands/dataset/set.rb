module NodeCtld
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
        zfs(
          :set,
          "#{k}=\"#{translate_property(k, v[i])}\"",
          "#{@pool_fs}/#{@name}"
        )
      end
    end
  end
end
