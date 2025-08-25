module NodeCtld
  class Commands::Vps::RemoveConfig < Commands::Base
    handle 4006
    needs :system, :osctl, :vps

    def exec
      cfg = VpsConfig.open(@pool_fs, @vps_id)
      cfg.destroy
      ok
    end

    def rollback
      cfg = VpsConfig.open(@pool_fs, @vps_id)
      cfg.restore
      ok
    end
  end
end
