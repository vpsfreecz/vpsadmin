module NodeCtld
  class Commands::Vps::Umount < Commands::Base
    handle 5303
    needs :system, :vps, :zfs

    def exec
      # TODO
    end

    def rollback
      # TODO
    end
  end
end
