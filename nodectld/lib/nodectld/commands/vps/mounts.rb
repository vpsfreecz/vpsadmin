module NodeCtld
  class Commands::Vps::Mounts < Commands::Base
    handle 5301
    needs :system, :vps, :zfs, :pool

    def exec
      # TODO
    end

    def rollback
      # TODO
    end
  end
end
