module VpsAdmind
  class Commands::Vps::Mounts < Commands::Base
    handle 5301
    needs :system, :vps, :zfs

    def exec
      action_script('mount')
      action_script('umount')
    end

    def rollback
      ok
    end
  end
end
