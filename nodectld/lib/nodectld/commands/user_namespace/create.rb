module NodeCtld
  class Commands::UserNamespace::Create < Commands::Base
    handle 7001
    needs :system, :osctl

    def exec
      osctl(%i(user new), @name, ugid: @ugid, offset: @offset, size: @size)
      ok
    end

    def rollback
      osctl(%i(user del), @name, {}, {}, {valid_rcs: [1]})
      ok
    end
  end
end
