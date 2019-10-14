module NodeCtld
  class Commands::Vps::SendRootfs < Commands::Base
    handle 3031
    needs :system, :osctl

    def exec
      osctl(%i(ct send rootfs), @vps_id)
    end

    def rollback
      ok
    end
  end
end
