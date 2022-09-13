module NodeCtld
  class Commands::UserNamespace::Destroy < Commands::Base
    handle 7002
    needs :system, :osctl

    def exec
      osctl_pool(@pool_name, %i(user del), @name)
      ok
    end

    def rollback
      osctl_pool(@pool_name, %i(user new), @name, {map_uid: @uidmap, map_gid: @gidmap})
      ok
    end
  end
end
