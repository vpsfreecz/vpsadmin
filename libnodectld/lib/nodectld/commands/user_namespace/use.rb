module NodeCtld
  class Commands::UserNamespace::Use < Commands::Base
    handle 7001
    needs :system, :osctl

    def exec
      OsCtlUsers.add_vps(
        pool_fs: @pool_fs,
        vps_id: @vps_id,
        user_name: @name,
        uidmap: @uidmap,
        gidmap: @gidmap,
      )
      ok
    end

    def rollback
      OsCtlUsers.remove_vps(
        pool_fs: @pool_fs,
        vps_id: @vps_id,
        user_name: @name,
      )
      ok
    end
  end
end
