module NodeCtld
  class Commands::UserNamespace::Disuse < Commands::Base
    handle 7002
    needs :system, :osctl

    def exec
      OsCtlUsers.remove_vps(
        pool_fs: @pool_fs,
        vps_id: @vps_id,
        user_name: @name,
      )
      ok
    end

    def rollback
      OsCtlUsers.add_vps(
        pool_fs: @pool_fs,
        vps_id: @vps_id,
        user_name: @name,
        uidmap: @uidmap,
        gidmap: @gidmap,
      )
      ok
    end
  end
end
