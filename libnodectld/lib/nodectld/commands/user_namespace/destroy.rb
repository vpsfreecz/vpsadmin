module NodeCtld
  class Commands::UserNamespace::Destroy < Commands::Base
    handle 7002
    needs :system, :osctl

    def exec
      osctl(%i(user del), @name)
      ok
    end

    def rollback
      osctl(%i(user new), @name, ugid: @ugid, offset: @offset, size: @size)
      ok
    end
  end
end
