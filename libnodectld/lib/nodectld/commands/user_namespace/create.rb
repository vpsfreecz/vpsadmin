module NodeCtld
  class Commands::UserNamespace::Create < Commands::Base
    handle 7001
    needs :system, :osctl

    def exec
      osctl(%i(user new), @name, map_uid: @uidmap, map_gid: @gidmap)
      ok
    end

    def rollback
      osctl(%i(user del), @name, {}, {}, {valid_rcs: [1]})
      ok
    end
  end
end
